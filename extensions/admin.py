# vim: tabstop=4 shiftwidth=4 softtabstop=4

# Copyright 2011 OpenStack LLC.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import base64
import datetime
import json

from nova import db
from nova import exception
from nova import flags
from nova import log as logging
from nova import utils
from nova import wsgi
from nova.auth import manager


from nova.api.openstack import extensions

FLAGS = flags.FLAGS
LOG = logging.getLogger('nova.api.openstack.admin')


def user_dict(user, base64_file=None):
    """Convert the user object to a result dict"""
    if user:
        return {
            'username': user.id,
            'accesskey': user.access,
            'secretkey': user.secret,
            'file': base64_file}
    else:
        return {}


def project_dict(project):
    """Convert the project object to a result dict"""
    if project:
        return {
            'id': project.id,
            'name': project.id,
            'projectname': project.id,
            'project_manager_id': project.project_manager_id,
            'description': project.description}
    else:
        return {}


def host_dict(host, compute_service, instances, volume_service, volumes, now):
    """Convert a host model object to a result dict"""
    rv = {'hostname': host, 'instance_count': len(instances),
          'volume_count': len(volumes)}
    if compute_service:
        latest = compute_service['updated_at'] or compute_service['created_at']
        delta = now - latest
        if delta.seconds <= FLAGS.service_down_time:
            rv['compute'] = 'up'
        else:
            rv['compute'] = 'down'
    if volume_service:
        latest = volume_service['updated_at'] or volume_service['created_at']
        delta = now - latest
        if delta.seconds <= FLAGS.service_down_time:
            rv['volume'] = 'up'
        else:
            rv['volume'] = 'down'
    return rv


def instance_dict(inst):
    return {'name': inst['name'],
            'memory_mb': inst['memory_mb'],
            'vcpus': inst['vcpus'],
            'disk_gb': inst['local_gb'],
            'flavor_id': inst['flavorid']}


def vpn_dict(project, vpn_instance):
    rv = {'project_id': project.id,
          'public_ip': project.vpn_ip,
          'public_port': project.vpn_port}
    if vpn_instance:
        rv['instance_id'] = ec2utils.id_to_ec2_id(vpn_instance['id'])
        rv['created_at'] = utils.isotime(vpn_instance['created_at'])
        address = vpn_instance.get('fixed_ip', None)
        if address:
            rv['internal_ip'] = address['address']
        if project.vpn_ip and project.vpn_port:
            if utils.vpn_ping(project.vpn_ip, project.vpn_port):
                rv['state'] = 'running'
            else:
                rv['state'] = 'down'
        else:
            rv['state'] = 'down - invalid project vpn config'
    else:
        rv['state'] = 'pending'
    return rv


class ProjectController(wsgi.Controller):

    def show(self, req, id):
        """Returns project data, including member ids."""
        return project_dict(manager.AuthManager().get_project(id))

    def index(self, req):
        """Returns all projects - should be changed to deal with a list."""
        user = req.environ.get('user')
        return {'projectSet':
            [project_dict(u) for u in
            manager.AuthManager().get_projects(user=user)]}

    def create(self, name, manager_user, description=None,
                         member_users=None):
        """Creates a new project"""
        msg = _("Create project %(name)s managed by"
                " %(manager_user)s") % locals()
        context = req.environ['nova.context']
        LOG.audit(msg, context=context)
        return project_dict(
            manager.AuthManager().create_project(
                name,
                manager_user,
                description=None,
                member_users=None))

    def update(self, name, manager_user, description=None):
        """Modifies a project"""
        msg = _("Modify project: %(name)s managed by"
                " %(manager_user)s") % locals()
        context = req.environ['nova.context']
        LOG.audit(msg, context=context)
        manager.AuthManager().modify_project(name,
                                             manager_user=manager_user,
                                             description=description)
        return True

    def delete(self, name):
        """Permanently deletes a project."""
        context = req.environ['nova.context']
        LOG.audit(_("Delete project: %s"), name, context=context)
        manager.AuthManager().delete_project(name)
        return True


class Admin(object):

    def __init__(self):
        pass

    def get_name(self):
        return "Admin COntroller"

    def get_alias(self):
        return "ADMIN"

    def get_description(self):
        return "The Admin API Extension"

    def get_namespace(self):
        return "http://www.fox.in.socks/api/ext/pie/v1.0"

    def get_updated(self):
        return "2011-01-22T13:25:27-06:00"

    def get_resources(self):
        resources = []
        resource = extensions.ResourceExtension('admin/projects',
                                                 ProjectController())
        resources.append(resource)
        return resources
