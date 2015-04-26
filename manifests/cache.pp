# examdb cache role
class examdb::cache (
) {

  case $::osfamily {
    'RedHat': {
      case $::operatingsystemrelease {
        /^5.*/,/^6.*/: {
          include ius
          $redis_version_override = '2.4.x'
        }
        default: {
        }
      }
      $redis_require = 'Yumrepo[epel]'
    }
    default: {
      $redis_require = undef
      $redis_version_override = undef
    }
  }

  class { 'redis':
    system_sysctl          => true,
    redis_version_override => $redis_version_override,
    require                => $redis_require,
  }
}
