class examdb (
  $server_domain = undef,
  $appname = 'examdb',
  $project_name = 'ubc/examdb',
  $doc_base = '/www_data/app',
  $web_root = 'web',
  $timezone = 'Canada/Pacific',
  $ensure = 'present',
  $host     = $fqdn,
  $port    = 80,
  $db_host = 'localhost',
  $db_user = 'examdb',
  $db_password = 'examdb',
  $db_name = 'examdb',
  $ssl = false,
  $ssl_cert = undef,
  $ssl_key = undef,
  $ssl_port = 443,
  $github_token = undef,
  $writable_dirs = undef,
) {
  include git

  case $::osfamily {
    'RedHat': {
      case $::operatingsystemrelease {
        /^5.*/,/^6.*/: {
          include ius
          $php_package_prefix = 'php54-'
          $composer_php_package = 'php54-cli'
          $php_require = [Package['nginx'], Class['ius']]
          $manage_nodejs_repo = true
          $nodejs_require = [Yumrepo['epel']]
        }
        /^7.*/: {
          include epel
          $php_package_prefix = 'php-'
          $composer_php_package = 'php-cli'
          $php_require = [Package['nginx'], Yumrepo['epel']]
          $manage_nodejs_repo = false
          $nodejs_require = [Yumrepo['epel']]
        }
        default: {
          fail("Unsupported platform: ${::operatingsystem} ${::operatingsystemrelease}")
        }
      }
      $php_extensions = {
        'pecl-zendopcache' => {
          settings => {
            'OpCache/opcache.enable'      => '1',
            'OpCache/opcache.use_cwd'     => '1',
            'OpCache/opcache.save_comments' => '1',
            'OpCache/opcache.load_comments' => '1',
          }
        },
        'xml' => {},
        'mcrypt' => {},
        'pdo' => {},
        'pecl-mongo' => {},
        'mbstring' => {},
        'intl' => {},
        'mysql' => {},
      }
      $nginx_user = 'nginx'
      $nginx_group = 'nginx'
    }
    'Debian': {
      case $::operatingsystemrelease {
        12.04: {
          $manage_nodejs_repo = true
        }
        default: {
          $manage_nodejs_repo = true
        }
      }
      $php_package_prefix = undef
      $php_require = [Package['nginx']]
      $php_extensions = {
        'mcrypt' => {},
        'mongo' => {},
      }
      $nginx_user = 'www-data'
      $nginx_group = 'www-data'
    }
    default: {
      fail("Unsupported platform: ${::operatingsystem} ${::operatingsystemrelease}")
    }
  }

  # we need an app user to run composer install as bower complains being running as root
  user { 'app':
    ensure  => present,
    groups  => [$nginx_group],
    home    => '/tmp',
    require => Package['nginx'],
  }

  # setup php
  class { 'php':
    ensure         => 'latest',
    fpm            => false,
    composer       => false,
    phpunit        => false,
    dev            => false,
    pear           => false,
    package_prefix => $php_package_prefix,
    extensions     => $php_extensions,
    require        => $php_require,
    settings       => {
        'Date/date.timezone' => $timezone,
    },
  } ->

  # install fpm and create app pool
  class { 'php::fpm':
    ensure => present,
    pools  => {},
  }

  php::fpm::pool { 'app':
    ensure => present,
    user   => $nginx_user,
    group  => $nginx_group,
  }

  # remove default pool
  php::fpm::pool { 'www':
    ensure => absent,
  }

  class { 'composer':
    php_package     => $composer_php_package,
    suhosin_enabled => false,
    github_token    => $github_token,
    require         => Class['php'],
  }

  # install application
  $base_dir = dirname($doc_base)
  exec { "create ${base_dir}":
    command => "mkdir -p ${base_dir}",
    creates => $base_dir,
    path    => '/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin',
  }->

  file { $base_dir:
    ensure  => present,
    owner   => 'app',
    mode    => '0755',
    require => User['app'],
  }->

  composer::project { $appname:
    project_name => $project_name,
    target_dir => $doc_base,
    stability => 'dev',
    keep_vcs  => true,
    dev       => $dev,
    user      => 'app',
  }->

  composer::exec { "${appname}-install":
      cmd         => 'install',
      cwd         => $doc_base,
      scripts     => true,
      timeout     => 0,
      dev         => false,
      prefer_dist => true,
      user        => 'app',
      interaction => false,
      unless      => "test -f ${doc_base}/vendor/autoload.php",
  }

  $writable_absolute_dirs = prefix($writable_dirs, "$doc_base/")
  if $writable_dirs {
    file { $writable_absolute_dirs:
      ensure  => directory,
      owner   => $nginx_user,
      recurse => true, 
      require => Composer::Exec["${appname}-install"]
     }
  }


  $server_name = $server_domain ? {
      undef => $::fqdn,
      default => $server_domain,
  }

  # setup nginx
  class { 'nginx': }

  nginx::resource::upstream { 'app':
    ensure  => present,
    members => [
      '127.0.0.1:9000',
    ],
  }

  nginx::resource::vhost {$server_name:
    ensure              => present,
    www_root            => "${doc_base}/${web_root}",
    location_cfg_append => { 'rewrite' => '^ https://$server_name$request_uri? permanent' },
  }

  nginx::resource::vhost {"$server_name ssl":
    ensure               => present,
    www_root             => "${doc_base}/${web_root}",
    listen_port		 => 443,
    server_name          => [$server_name],
    vhost_cfg_prepend    => {
      'add_header' => "X-APP-Server ${::hostname}"
    },
    ssl                  => $ssl,
    ssl_cert             => $ssl_cert,
    ssl_key              => $ssl_key,
    proxy_set_header     => ['Host $host', 'X-Real-IP $remote_addr', 'X-Forwarded-For $proxy_add_x_forwarded_for'],
    try_files		 => ['$uri /app.php$is_args$args'],
  }

  nginx::resource::location { "php_${server_name}":
    ensure               => present,
    vhost                => "$server_name ssl",
    location             => '~ ^/app\.php(/|$)',
    ssl			 => true,
    ssl_only		 => true,
    fastcgi              => 'app',
    fastcgi_split_path   => '^(.+\.php)(/.*)$',
    fastcgi_script       => "${doc_base}/${web_root}/\$fastcgi_script_name",
    fastcgi_param        => {
      'HTTPS'		=> '$https',
    },
    location_cfg_prepend => {
      fastcgi_read_timeout => 600,
      'internal' => ''
    },
  }

  $real_ports = $ssl ? {
    true => [$port, '443'],
    default => [$port]
  }

  firewall { '100 allow http and https access':
    port   => $real_ports,
    proto  => tcp,
    action => accept,
  }
}
