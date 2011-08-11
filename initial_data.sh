#!/bin/bash
BIN_DIR=${BIN_DIR:-.}
# Tenants
$BIN_DIR/keystone-manage $* tenant add admin
$BIN_DIR/keystone-manage $* tenant add demo

# Users
$BIN_DIR/keystone-manage $* user add demo secrete demo
$BIN_DIR/keystone-manage $* user add admin secrete admin

# Roles
$BIN_DIR/keystone-manage $* role add Admin
$BIN_DIR/keystone-manage $* role add Member
$BIN_DIR/keystone-manage $* role grant Admin admin

#endpointTemplates
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne swift http://localhost:8080/v1/AUTH_%tenant_id% http://localhost:8080/ http://localhost:8080/v1/AUTH_%tenant_id% 1 1
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne nova_compat http://localhost:8774/v1.0/ http://localhost:8774/v1.0  http://localhost:8774/v1.0 1 1
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne nova http://localhost:8774/v1.1/ http://localhost:8774/v1.1  http://localhost:8774/v1.1 1 1
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne glance http://localhost:9292/v1.1/%tenant_id% http://localhost:9292/v1.1/%tenant_id% http://localhost:9292/v1.1/%tenant_id% 1 1
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne keystone http://localhost:8080/v2.0 http://localhost:8081/v2.0 http://localhost:8080/v2.0 1 1
$BIN_DIR/keystone-manage $* endpointTemplates add RegionOne identity http://localhost:5000/v2.0 http://localhost:5001/v2.0 http://localhost:5000/v2.0 1 1

# Tokens
$BIN_DIR/keystone-manage $* token add 999888777666 admin admin 2015-02-05T00:00

#Tenant endpoints
$BIN_DIR/keystone-manage $* endpoint add admin 1
$BIN_DIR/keystone-manage $* endpoint add admin 2
$BIN_DIR/keystone-manage $* endpoint add admin 3
$BIN_DIR/keystone-manage $* endpoint add admin 4
$BIN_DIR/keystone-manage $* endpoint add admin 5
$BIN_DIR/keystone-manage $* endpoint add admin 6

$BIN_DIR/keystone-manage $* endpoint add demo 1
$BIN_DIR/keystone-manage $* endpoint add demo 2
$BIN_DIR/keystone-manage $* endpoint add demo 3
$BIN_DIR/keystone-manage $* endpoint add demo 4
$BIN_DIR/keystone-manage $* endpoint add demo 5
$BIN_DIR/keystone-manage $* endpoint add demo 6
