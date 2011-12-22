#!/usr/bin/env bash
API_DIR=$DIR/openstackx
set -o errexit
set -o xtrace

DIR=`pwd`
CMD=$1

USE_GIT=${USE_GIT:-1}

if [ "$CMD" = "branch" ]; then
    if [ "$USE_GIT" == 1 ]; then
        SOURCE_BRANCH=${2:-master}
    else
        SOURCE_BRANCH=${2:-lp:nova}
    fi
    DIRNAME=${3:-nova}
else
    DIRNAME=${2:-nova}
fi

NOVA_DIR=$DIR/$DIRNAME
DASH_DIR=$DIR/dash
GLANCE_DIR=$DIR/glance
KEYSTONE_DIR=$DIR/keystone
NOVACLIENT_DIR=$DIR/python-novaclient
API_DIR=$DIR/openstackx
NOVNC_DIR=$DIR/noVNC

if [ ! -n "$HOST_IP" ]; then
    # NOTE(vish): This will just get the first ip in the list, so if you
    #             have more than one eth device set up, this will fail, and
    #             you should explicitly set HOST_IP in your environment
    HOST_IP=`LC_ALL=C ifconfig  | grep -m 1 'inet addr:'| cut -d: -f2 | awk '{print $1}'`
fi

# OPENSTACK COMPONENTS
ENABLE_VOLUMES=${ENABLE_VOLUMES:-0}
ENABLE_DASH=${ENABLE_DASH:-1}
ENABLE_KEYSTONE=${ENABLE_KEYSTONE:-1}
ENABLE_GLANCE=${ENABLE_GLANCE:-1}
ENABLE_APACHE=${ENABLE_APACHE:-0}
ENABLE_SYSLOG=${ENABLE_SYSLOG:-0}
ENABLE_NOVACLIENT=${ENABLE_NOVACLIENT:-1}

# NOVA CONFIGURATION
USE_MYSQL=${USE_MYSQL:-0}
INTERFACE=${INTERFACE:-eth0}
FLOATING_RANGE=${FLOATING_RANGE:-10.6.0.0/27}
FIXED_RANGE=${FIXED_RANGE:-10.0.0.0/24}
MYSQL_PASS=${MYSQL_PASS:-nova}
TEST=${TEST:-0}
USE_LDAP=${USE_LDAP:-0}
# Use OpenDJ instead of OpenLDAP when using LDAP
USE_OPENDJ=${USE_OPENDJ:-0}
# Use IPv6
USE_IPV6=${USE_IPV6:-0}
LIBVIRT_TYPE=${LIBVIRT_TYPE:-qemu}
NET_MAN=${NET_MAN:-VlanManager}
# NOTE(vish): If you are using FlatDHCP on multiple hosts, set the interface
#             below but make sure that the interface doesn't already have an
#             ip or you risk breaking things.
# FLAT_INTERFACE=eth0

if [ "$USE_MYSQL" == 1 ]; then
    SQL_CONN=mysql://root:$MYSQL_PASS@localhost/nova
else
    SQL_CONN=sqlite:///$NOVA_DIR/nova.sqlite
fi

if [ "$USE_LDAP" == 1 ]; then
    AUTH=ldapdriver.LdapDriver
else
    AUTH=dbdriver.DbDriver
fi

if [ "$CMD" == "branch" ]; then
    rm -rf $NOVA_DIR
    if [ "$USE_GIT" == 1 ]; then
        sudo apt-get install -y git-core
        git clone https://github.com/openstack/nova.git $NOVA_DIR
        cd $NOVA_DIR
        git checkout $SOURCE_BRANCH
    else
        sudo apt-get install -y bzr
        if [ ! -e "$DIR/.bzr" ]; then
            bzr init-repo $DIR
        fi
        bzr branch $SOURCE_BRANCH $NOVA_DIR
        cd $NOVA_DIR
    fi
    mkdir -p $NOVA_DIR/instances
    mkdir -p $NOVA_DIR/networks
    if [ "$ENABLE_KEYSTONE" == 1 ]; then
        # allow keystone code to be imported into nova
        ln -s $KEYSTONE_DIR/keystone $NOVA_DIR/keystone
    fi
    exit
fi

# You should only have to run this once
if [ "$CMD" == "install" ]; then
    sudo apt-get install -y python-software-properties
    sudo add-apt-repository ppa:nova-core/trunk
    sudo apt-get update
    sudo apt-get install -y dnsmasq-base kpartx kvm gawk iptables ebtables wget sudo \
        kvm libvirt-bin screen vlan curl rabbitmq-server socat unzip psmisc euca2ools
    if [ "$ENABLE_VOLUMES" == 1 ]; then
        sudo apt-get install -y lvm2 iscsitarget open-iscsi
        echo "ISCSITARGET_ENABLE=true" | sudo tee /etc/default/iscsitarget
        sudo /etc/init.d/iscsitarget restart
    fi
    sudo modprobe kvm || true
    sudo /etc/init.d/libvirt-bin restart
    sudo modprobe nbd || true
    sudo apt-get install -y python-mox python-ipy python-paste python-migrate \
        python-gflags python-greenlet python-libvirt python-libxml2 python-routes \
        python-netaddr python-pastedeploy python-eventlet python-novaclient \
        python-glance python-cheetah python-carrot python-tempita \
        python-sqlalchemy python-suds python-lockfile python-m2crypto python-boto

    rm -rf $API_DIR
    rm -rf $NOVNC_DIR
    git clone git://github.com/cloudbuilders/openstackx.git $API_DIR
    git clone git://github.com/openstack/noVNC.git $NOVNC_DIR

    if [ "$ENABLE_DASH" == 1 ]; then
        sudo apt-get install bzr git-core python-setuptools python-dev -y
        sudo easy_install virtualenv
        rm -rf $DASH_DIR
        git clone git://github.com/openstack/horizon.git $DASH_DIR
        cd $DASH_DIR/openstack-dashboard
        cp local/local_settings.py.example local/local_settings.py
        python tools/install_venv.py
        tools/with_venv.sh dashboard/manage.py syncdb
        if [ "$ENABLE_APACHE" == 1 ]; then
            sudo apt-get install -y apache2 libapache2-mod-wsgi
            mkdir $DASH_DIR/.blackhole

            cat > $DASH_DIR/openstack-dashboard/dashboard/wsgi/local.wsgi <<EOF
import sys
sys.path.append('/opt/dash/openstack-dashboard/.dashboard-venv/lib/python2.6/site-packages/')
sys.path.append('/opt/dash/openstack-dashboard/.dashboard-venv/lib/python2.7/site-packages/')
sys.path.append('/opt/dash/openstack-dashboard/')
sys.path.append('/opt/dash/django-openstack/')
sys.path.append('/opt/openstackx')
sys.path.append('/opt/dash/openstack-dashboard/.dashboard-venv/src/openstack')

EOF
            cat $DASH_DIR/openstack-dashboard/dashboard/wsgi/django.wsgi >> $DASH_DIR/openstack-dashboard/dashboard/wsgi/local.wsgi

            cat > /etc/apache2/sites-enabled/000-default <<EOF
<VirtualHost *:80>
    WSGIScriptAlias / $DASH_DIR/openstack-dashboard/dashboard/wsgi/local.wsgi
    WSGIDaemonProcess dashboard user=www-data group=www-data processes=3 threads=10
    WSGIProcessGroup dashboard

    DocumentRoot $DASH_DIR/.blackhole/
    Alias /media $DASH_DIR/openstack-dashboard/media

    <Directory />
        Options FollowSymLinks
        AllowOverride None
    </Directory>

    <Directory $DASH_DIR/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride None
        Order allow,deny
        allow from all
    </Directory>

    ErrorLog /var/log/apache2/error.log
    LogLevel warn
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

            chown -R www-data:www-data $DASH_DIR
        fi
    fi

    if [ "$ENABLE_GLANCE" == 1 ]; then
        rm -rf $GLANCE_DIR
        sudo apt-get install -y bzr python-eventlet python-routes python-greenlet \
            python-argparse python-sqlalchemy python-wsgiref \
            python-pastedeploy python-xattr
        bzr branch lp:glance $GLANCE_DIR
        sudo mkdir -p /var/log/glance

        if [ "$ENABLE_DASH" == 1 ]; then
           ln -s $GLANCE_DIR/glance $DASH_DIR/openstack-dashboard/dashboard/glance
        fi

        if [ "$ENABLE_SYSLOG" == 1 ]; then
            sed -e '/^handlers=devel$/s/=devel/=production/' \
                $GLANCE_DIR/etc/logging.cnf.sample \
                >$GLANCE_DIR/etc/logging.cnf
        fi
    fi

    if [ "$ENABLE_KEYSTONE" == 1 ]; then
        sudo apt-get install -y git-core python-setuptools python-dev python-lxml \
            python-pastescript python-pastedeploy python-paste sqlite3 \
            python-pysqlite2 python-sqlalchemy python-webob python-greenlet \
            python-routes libldap2-dev libsasl2-dev
        rm -rf $KEYSTONE_DIR
        git clone https://github.com/openstack/keystone.git $KEYSTONE_DIR

        if [ "$ENABLE_SYSLOG" == 1 ]; then
            sed -i -e '/^handlers=devel$/s/=devel/=production/' \
                $KEYSTONE_DIR/etc/logging.cnf
        fi
    fi

    if [ "$ENABLE_NOVACLIENT" == 1 ]; then
        rm -rf $NOVACLIENT_DIR
        git clone https://github.com/rackspace/python-novaclient.git $NOVACLIENT_DIR
        cd $NOVACLIENT_DIR
        sudo python setup.py develop
    fi

    if [ "$ENABLE_SYSLOG" == 1 ]; then
        sudo sed -i -e '
            /ModLoad.*imudp/s/^[#]//
            /UDPServerRun/s/^[#]//
        ' /etc/rsyslog.conf
        sudo /usr/sbin/service rsyslog restart
    fi

    if [ "$USE_IPV6" == 1 ]; then
        sudo apt-get install -y radvd
        sudo bash -c "echo 1 > /proc/sys/net/ipv6/conf/all/forwarding"
        sudo bash -c "echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra"
    fi

    if [ "$USE_MYSQL" == 1 ]; then
        cat <<MYSQL_PRESEED | debconf-set-selections
mysql-server-5.1 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.1 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.1 mysql-server/start_on_boot boolean true
MYSQL_PRESEED
        sudo apt-get install -y mysql-server python-mysqldb
    else
        sudo apt-get install -y sqlite3 python-pysqlite2
    fi
    mkdir -p $DIR/images
    wget -c http://images.ansolabs.com/tty.tgz
    tar -C $DIR/images -zxf tty.tgz
    exit
fi

# Configure screen
cat >~/.screenrc <<EOF
hardstatus on
hardstatus alwayslastline
hardstatus string "%{.bW}%-w%{.rW}%n %t%{-}%+w %=%{..G}%H %{..Y}%d/%m %c"

defscrollback 1024

vbell off
startup_message off
EOF

NL=`echo -ne '\015'`

function screen_it {
    screen -S nova -X screen -t $1
    screen -S nova -p $1 -X stuff "$2$NL"
}

function add_nova_flag {
    echo "$1" >> $NOVA_DIR/bin/nova.conf
}

if [ "$CMD" == "run" ] || [ "$CMD" == "run_detached" ]; then

    rm -f $NOVA_DIR/bin/nova.conf

    add_nova_flag "--verbose"
    add_nova_flag "--nodaemon"
    add_nova_flag "--dhcpbridge_flagfile=$NOVA_DIR/bin/nova.conf"
    add_nova_flag "--network_manager=nova.network.manager.$NET_MAN"
    add_nova_flag "--my_ip=$HOST_IP"
    add_nova_flag "--public_interface=$INTERFACE"
    add_nova_flag "--vlan_interface=$INTERFACE"
    add_nova_flag "--sql_connection=$SQL_CONN"
    add_nova_flag "--auth_driver=nova.auth.$AUTH"
    add_nova_flag "--libvirt_type=$LIBVIRT_TYPE"
    add_nova_flag "--osapi_extensions_path=$API_DIR/extensions"
    add_nova_flag "--vncproxy_url=http://$HOST_IP:6080"
    add_nova_flag "--vncproxy_wwwroot=$DIR/noVNC/noVNC"

    if [ -n "$FLAT_INTERFACE" ]; then
        add_nova_flag "--flat_interface=$FLAT_INTERFACE"
    fi

    if [ "$USE_IPV6" == 1 ]; then
        add_nova_flag "--use_ipv6"
    fi

    if [ "$ENABLE_KEYSTONE" == 1 ]; then
        add_nova_flag "--api_paste_config=$KEYSTONE_DIR/examples/paste/nova-api-paste.ini"
    fi

    if [ "$ENABLE_GLANCE" == 1 ]; then
        add_nova_flag "--image_service=nova.image.glance.GlanceImageService"
    fi

    if [ "$ENABLE_SYSLOG" == 1 ]; then
        add_nova_flag "--use_syslog=1"
    fi

    killall dnsmasq || true
    if [ "$USE_IPV6" == 1 ]; then
       killall radvd
    fi
    screen -d -m -S nova -t nova
    sleep 1
    if [ "$USE_MYSQL" == 1 ]; then
        mysql -p$MYSQL_PASS -e 'DROP DATABASE nova;'
        mysql -p$MYSQL_PASS -e 'CREATE DATABASE nova;'
    else
        rm -f $NOVA_DIR/nova.sqlite
    fi

    rm -rf $NOVA_DIR/instances
    mkdir -p $NOVA_DIR/instances
    rm -rf $NOVA_DIR/networks
    mkdir -p $NOVA_DIR/networks

    if [ "$TEST" == 1 ]; then
        cd $NOVA_DIR
        python $NOVA_DIR/run_tests.py
        cd $DIR
    fi

    # create the database
    $NOVA_DIR/bin/nova-manage db sync
    if [ "$ENABLE_KEYSTONE" == 0 ]; then
        if [ "$USE_LDAP" == 1 ]; then
            if [ "$USE_OPENDJ" == 1 ]; then
                add_nova_flag "--ldap_user_dn=cn=Directory Manager"
                $NOVA_DIR/nova/auth/opendj.sh
            else
                $NOVA_DIR/nova/auth/slap.sh
            fi
        fi

    else
        rm -f keystone.db
        # add default data
        curl -OL https://raw.github.com/cloudbuilders/deploy.sh/master/initial_data.sh
        BIN_DIR=$KEYSTONE_DIR/bin bash initial_data.sh
    fi
    # create an admin user called 'admin'
    $NOVA_DIR/bin/nova-manage user admin admin admin admin
    # create a project called 'admin' with project manager of 'admin'
    $NOVA_DIR/bin/nova-manage project create admin admin
    # create a small network
    $NOVA_DIR/bin/nova-manage network create private $FIXED_RANGE 1 32

    # create some floating ips
    $NOVA_DIR/bin/nova-manage floating create $FLOATING_RANGE

    # nova api crashes if we start it with a regular screen command,
    # so send the start command by forcing text into the window.
    screen_it n-api "$NOVA_DIR/bin/nova-api"
    if [ "$ENABLE_GLANCE" == 1 ]; then
        rm -rf /var/lib/glance/images/*
        rm -f $GLANCE_DIR/glance.sqlite
        LOG_ARG=""
        if [ "$ENABLE_SYSLOG" == 1 ]; then
            LOG_ARG="--log-config $GLANCE_DIR/etc/logging.cnf"
        fi
        screen_it g-api "cd $GLANCE_DIR; bin/glance-api --config-file=etc/glance-api.conf $LOG_ARG"
        sleep 2
        screen_it g-reg "cd $GLANCE_DIR; bin/glance-registry --config-file=etc/glance-registry.conf $LOG_ARG"

        # wait 10 seconds to let glance launch
        sleep 10
    else
        if [ ! -d "$NOVA_DIR/images" ]; then
            ln -s $DIR/images $NOVA_DIR/images
        fi
        screen_it objstore "$NOVA_DIR/bin/nova-objectstore"
    fi

    # remove previously converted images
    rm -rf $DIR/images/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]

    # convert old images - requires configured imageservice to be running
    $NOVA_DIR/bin/nova-manage image convert $DIR/images

    screen_it comp "$NOVA_DIR/bin/nova-compute"
    screen_it net "$NOVA_DIR/bin/nova-network"
    screen_it sched "$NOVA_DIR/bin/nova-scheduler"
    if [ "$ENABLE_KEYSTONE" == 1 ]; then
        LOG_ARG=""
        if [ "$ENABLE_SYSLOG" == 1 ]; then
            LOG_ARG="--log-config $KEYSTONE_DIR/etc/logging.cnf"
        fi
        screen_it keyst "$KEYSTONE_DIR/bin/keystone --config-file $KEYSTONE_DIR/etc/keystone.conf $LOG_ARG"
    fi
    if [ "$ENABLE_VOLUMES" == 1 ]; then
        screen_it vol "$NOVA_DIR/bin/nova-volume"
    fi
    if [ "$ENABLE_DASH" == 1 ]; then
        if [ "$ENABLE_APACHE" == 1 ]; then
            sudo /etc/init.d/apache2 restart
            screen_it apache "tail -f /var/log/apache2/error.log"
        else
            screen_it dash "cd $DASH_DIR/openstack-dashboard; tools/with_venv.sh dashboard/manage.py runserver 0.0.0.0:80"
        fi
    fi
    sleep 2
    screen_it vnc "$NOVA_DIR/bin/nova-vncproxy"
    sleep 2
    # export environment variables for project 'admin' and user 'admin'
    $NOVA_DIR/bin/nova-manage project zipfile admin admin $NOVA_DIR/nova.zip
    unzip -o $NOVA_DIR/nova.zip -d $NOVA_DIR/
    screen_it test "export PATH=$NOVA_DIR/bin:$PATH;. $NOVA_DIR/novarc; export NOVA_API_KEY=secrete; export NOVA_URL=http://localhost:5000/v2.0/"
    if [ "$CMD" != "run_detached" ]; then
      screen -S nova -x
    fi
fi

if [ "$CMD" == "run" ] || [ "$CMD" == "terminate" ]; then
    echo "FIXME: shutdown instances"
    echo "FIXME: delete volumes"
    echo "FIXME: clean networks?"
fi

if [ "$CMD" == "run" ] || [ "$CMD" == "clean" ]; then
    screen -S nova -X quit
    rm -f *.pid*
fi

if [ "$CMD" == "scrub" ]; then
    $NOVA_DIR/tools/clean-vlans
    if [ "$LIBVIRT_TYPE" == "uml" ]; then
        virsh -c uml:///system list | grep i- | awk '{print $1}' | xargs -n1 virsh -c uml:///system destroy
    else
        virsh list | grep i- | awk '{print $1}' | xargs -n1 virsh destroy
    fi
fi
