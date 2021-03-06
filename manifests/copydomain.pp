# == Define: orawls::copydomain
#
#   copydomain to an other nodes
##
define orawls::copydomain (
  $version                    = hiera('wls_version'               , 1111),  # 1036|1111|1211|1212
  $middleware_home_dir        = hiera('wls_middleware_home_dir'   , undef), # /opt/oracle/middleware11gR1
  $weblogic_home_dir          = hiera('wls_weblogic_home_dir'     , undef), # /opt/oracle/middleware11gR1/wlserver_103
  $jdk_home_dir               = hiera('wls_jdk_home_dir'          , undef), # /usr/java/jdk1.7.0_45
  $domain_name                = hiera('domain_name'               , undef),
  $adminserver_address        = hiera('domain_adminserver_address', "localhost"),
  $adminserver_port           = hiera('domain_adminserver_port'   , 7001),
  $userConfigFile             = hiera('domain_user_config_file'   , undef),
  $userKeyFile                = hiera('domain_user_key_file'      , undef),
  $weblogic_user              = hiera('wls_weblogic_user'         , "weblogic"),
  $weblogic_password          = hiera('domain_wls_password'       , undef),
  $os_user                    = hiera('wls_os_user'               , undef), # oracle
  $os_group                   = hiera('wls_os_group'              , undef), # dba
  $download_dir               = hiera('wls_download_dir'          , undef), # /data/install
  $log_dir                    = hiera('wls_log_dir'               , undef), # /data/logs
  $log_output                 = false, # true|false
)
{

  if $::override_weblogic_domain_folder == undef {
    $domains_path_dir = "${middleware_home_dir}/user_projects/domains"
    $apps_path_dir    = "${middleware_home_dir}/user_projects/applications"
  } else {
    $domains_path_dir = "${::override_weblogic_domain_folder}/domains"
    $apps_path_dir    = "${::override_weblogic_domain_folder}/applications"
  }

  if ( $version == 1036 or $version == 1111 or $version == 1211 ) {
    $nodeMgrHome = "${weblogic_home_dir}/common/nodemanager"

  } elsif $version == 1212 {
    if $::override_weblogic_domain_folder == undef {
      $nodeMgrHome = "${weblogic_home_dir}/../user_projects/domains/${domain_name}/nodemanager"
    } else {
      $nodeMgrHome = "${::override_weblogic_domain_folder}/domains/${domain_name}/nodemanager"
    }

  } else {
    $nodeMgrHome = "${weblogic_home_dir}/common/nodemanager"
  }

  # check if the domain already exists
  $found = domain_exists("${domains_path_dir}/${domain_name}", $version, $domains_path_dir)

  if $found == undef {
    $continue = true
  } else {
    if ($found) {
      $continue = false
    } else {
      notify { "orawls::wlsdomain ${title} ${domains_path_dir}/${domain_name} ${version} does not exists": }
      $continue = true
    }
  }

  if ($continue) {
    $exec_path = "${jdk_home_dir}/bin:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin"

    if $log_dir != undef {

      # create all log folders
      if !defined(Exec["create ${log_dir} directory"]) {
        exec { "create ${log_dir} directory":
          command => "mkdir -p ${log_dir}",
          unless  => "test -d ${log_dir}",
          user    => 'root',
          path    => $exec_path,
        }
      }
      if !defined(File[$log_dir]) {
        file { $log_dir:
          ensure  => directory,
          recurse => false,
          replace => false,
          require => Exec["create ${log_dir} directory"],
          mode    => '0775',
          owner   => $os_user,
          group   => $os_group,
        }
      }
    }

    if $::override_weblogic_domain_folder == undef {
      # make the default domain folders
      if !defined(File["weblogic_domain_folder"]) {
        # check oracle install folder
        file { "weblogic_domain_folder":
          ensure  => directory,
          path    => "${middleware_home_dir}/user_projects",
          recurse => false,
          replace => false,
          mode    => '0775',
          owner   => $os_user,
          group   => $os_group,
        }
      }
    } else {
      # make override domain folders

      if !defined(File["weblogic_domain_folder"]) {
        # check oracle install folder
        file { "weblogic_domain_folder":
          ensure  => directory,
          path    => $::override_weblogic_domain_folder,
          recurse => false,
          replace => false,
          mode    => '0775',
          owner   => $os_user,
          group   => $os_group,
        }
      }
    }

    if !defined(File[$domains_path_dir]) {
      # check oracle install folder
      file { $domains_path_dir:
        ensure  => directory,
        recurse => false,
        replace => false,
        mode    => '0775',
        owner   => $os_user,
        group   => $os_group,
        require => File["weblogic_domain_folder"],
      }
    }

    if !defined(File[$apps_path_dir]) {
      # check oracle install folder
      file { $apps_path_dir:
        ensure  => directory,
        recurse => false,
        replace => false,
        mode    => '0775',
        owner   => $os_user,
        group   => $os_group,
        require => File["weblogic_domain_folder"],
      }
    }

    # copy domain from the adminserver to the this node ( with scp and without passwords )
    exec { "copy domain jar ${domain_name}":
      command   => "scp -oStrictHostKeyChecking=no -oCheckHostIP=no ${os_user}@${adminserver_address}:${download_dir}/domain_${domain_name}.jar ${download_dir}/domain_${domain_name}.jar",
      path      => $exec_path,
      user      => $os_user,
      group     => $os_group,
      logoutput => $log_output,
    }

    $unPackCommand = "-domain=${domains_path_dir}/${domain_name} -template=${download_dir}/domain_${domain_name}.jar -app_dir=${apps_path_dir} -log=${download_dir}/domain_${domain_name}.log -log_priority=INFO"

    exec { "unpack ${domain_name}":
      command   => "${weblogic_home_dir}/common/bin/unpack.sh ${unPackCommand} -user_name=${weblogic_user} -password=${weblogic_password}",
      path      => $exec_path,
      user      => $os_user,
      group     => $os_group,
      logoutput => $log_output,
      require   => [File[$domains_path_dir],
                    Exec["copy domain jar ${domain_name}"]],
    }

    # the enroll domain.py used by the wlst
    file { "enroll.py ${domain_name} ${title}":
      path    => "${download_dir}/enroll_domain_${domain_name}.py",
      content => template("orawls/wlst/enrollDomain.py.erb"),
      ensure  => present,
      replace => true,
      mode    => '0775',
      owner   => $os_user,
      group   => $os_group,
      backup  => false,
    }

    exec { "execwlst ${domain_name} ${title}":
      command     => "${weblogic_home_dir}/common/bin/wlst.sh ${download_dir}/enroll_domain_${domain_name}.py ${weblogic_password}",
      environment => ["JAVA_HOME=${jdk_home_dir}"],
      path        => $exec_path,
      user        => $os_user,
      group       => $os_group,
      logoutput   => $log_output,
      require     => [File["${download_dir}/enroll_domain_${domain_name}.py"],
                      Exec["unpack ${domain_name}"]],
    }

    exec { "domain.py ${domain_name} ${title}":
      command   => "rm ${download_dir}/enroll_domain_${domain_name}.py",
      path      => $exec_path,
      user      => $os_user,
      group     => $os_group,
      logoutput => $log_output,
      require   => Exec["execwlst ${domain_name} ${title}"],
    }

  }
}
