#
# Recipe:: stagemonitor 
#
#
# Include necessary recipes
include_recipe "yum::default"
include_recipe "java::openjdk"
include_recipe "python"
include_recipe "python::pip"

# Necessary package gcc for twisted
package "gcc" do
  action :install
  not_if "rpm -q gcc"
end

# Install necessary packages
%w{supervisor git wget curl graphite-web python-carbon}.each do |pkg|
  yum_package pkg do
    action :install
  end
end

%w{/www/data/grafana /www/data/kibana}.each do |dir|
  directory dir do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
    action :create
  end
end


directory "/var/lib/carbon" do
  owner 'carbon'
  group 'carbon'
  action :create
end


mountpoints = []
mount = "/var/lib/carbon"
device = "/dev/xvdk"
directory mount do
  action :create
end
bash "Format device: #{device}" do
    __command = "mkfs.ext4 #{device}"
    __fs_check = 'dumpe2fs'

    code __command

    not_if "#{__fs_check} #{device}"
end
mount mount do
  device device
  fstype "ext4"
  options "noatime"
  action [:enable, :mount]
end
mountpoints << mount


# Elasticsearch 
execute "elasticsearch: version-1.3.4" do
  command "rpm -U --nodeps --force https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.3.4.noarch.rpm"
not_if "rpm -qa | grep -q 'elasticsearch-1.3.4'"
  action :nothing
end.run_action(:run)

# Grafana, Kibana
bash "grafana: install" do
  guard_interpreter :bash
  code "cd /tmp && wget http://grafanarel.s3.amazonaws.com/grafana-1.8.1.tar.gz && tar xzvf grafana-1.8.1.tar.gz && rm grafana-1.8.1.tar.gz && mv /tmp/grafana-1.8.1/* /www/data/grafana"
  not_if "test -f /www/data/grafana/index.html"
end

bash "kibana: install" do
  guard_interpreter :bash
  code "cd /tmp && wget https://download.elasticsearch.org/kibana/kibana/kibana-3.1.1.tar.gz && tar xzvf kibana-3.1.1.tar.gz && rm kibana-3.1.1.tar.gz && mv /tmp/kibana-3.1.1/* /www/data/kibana"
  not_if "test -f /www/data/kibana/index.html"
end

template "/etc/httpd/conf.d/graphite-web.conf" do
  source "sm-graphite-web.conf.erb"
  owner  "root"
  group  "root"
  mode   "0644"
end

template "/etc/graphite-web/local_settings.py" do
  source "sm-local_settings.py.erb"
  owner  "root"
  group  "root"
  mode   "0644"
end

template "/www/data/grafana/config.js" do
  source "sm-grafana-config.js.erb"
  owner 'root'
  group 'root'
  mode "0644"
end

template "/www/data/kibana/config.js" do
  source "sm-kibana-config.js.erb"
  owner 'root'
  group 'root'
  mode "0644"
end

template "/etc/supervisord.conf" do
  source "sm-supervisord.conf.erb"
  owner 'root'
  group 'root'
  mode "0644"
end

template "/usr/local/bin/run_elasticsearch" do
  source "sm-run.erb"
  owner 'root'
  group 'root'
  mode "0777"
end

# Let's enable the carbon-cache service
service "carbon-cache" do
    supports :status => true, :restart => true, :reload => true
    action [ :enable, :start ]
end

# Let's enable apache 
service "httpd" do
  action [:enable, :start]
end

# Let's enable elasticsearch service
service "elasticsearch" do
    supports :status => true, :restart => true, :reload => true
    action [ :enable, :start ]
end

# Let's make sure the sqlite3 graphite database is created
execute "graphite-admin: database" do
  command "/usr/lib/python2.6/site-packages/graphite/manage.py syncdb --noinput"
  action :run
end
