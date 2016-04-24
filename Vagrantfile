# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 1.5.1"

if ENV['VAGRANT_HOME'].nil?
      ENV['VAGRANT_HOME'] = './'
end

examdb = {
  :'centos66' => { :memory => '512', :ip => '10.1.1.10', :box => 'puppetlabs/centos-6.6-64-puppet',   :box_version => '1.0.1', :domain => 'examdb.dev' },
  :'centos7'  => { :memory => '512', :ip => '10.1.1.11', :box => 'puppetlabs/centos-7.0-64-puppet',   :box_version => '1.0.1', :domain => 'examdb.dev' },
  :'precise'  => { :memory => '512', :ip => '10.1.1.20', :box => 'puppetlabs/ubuntu-12.04-64-puppet', :box_version => '1.0.1', :domain => 'examdb.dev' },
  :'trusty'   => { :memory => '512', :ip => '10.1.1.21', :box => 'puppetlabs/ubuntu-14.04-64-puppet', :box_version => '1.0.1', :domain => 'examdb.dev' },
}
Vagrant.configure("2") do |config|
  examdb.each_pair do |name, opts|
    config.vm.define name do |n|
      config.vm.provider :virtualbox do |vb|
        vb.customize ["modifyvm", :id, "--memory", opts[:memory] ]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end
      n.vm.network "private_network", ip: opts[:ip]
      n.vm.box = opts[:box]
      n.vm.box_version = opts[:box_version]
      n.vm.synced_folder "#{ENV['VAGRANT_HOME']}","/etc/puppet/modules/examdb"
      if "#{name}" == "trusty" or "#{name}" == "saucy" or "#{name}" == "precise"
        n.vm.provision :shell, :inline => "apt-get update"
        #n.vm.provision :shell, :inline => "apt-get -y upgrade"
        #n.vm.provision :shell, :inline => "apt-get install ruby rubygems"
        #n.vm.provision :shell, :inline => "gem install puppet facter --no-ri --no-rdoc"
      end
      n.vm.provision :shell, :inline => <<-SHELL
        puppet module install jfryman-nginx --version 0.2.5
        puppet module install puppetlabs-git
        puppet module install tPl0ch-composer
        puppet module install puppetlabs-firewall
        puppet module install mayflower-php
        puppet module install puppetlabs-mysql
        puppet module install thias-fooacl
        puppet module install stahnma-epel
        puppet module install kemra102-ius
        puppet module install fsalum-redis
      SHELL

      n.vm.provision "puppet" do |puppet|
        puppet.manifests_path = "spec/fixtures/manifests"
        puppet.manifest_file  = "site.pp"
        puppet.hiera_config_path = "spec/fixtures/hiera.yaml"
        puppet.options = "--environment", "dev"
      end
    end
  end
end
