# == Defined resource type: ipmi::network
#

define ipmi::network (
  $ip = '0.0.0.0',
  $netmask = '255.255.255.0',
  $gateway = '0.0.0.0',
  $type = 'dhcp',
  $lan_channel = 1,
  $interface = 'failover',
  $vlan = 0,
)
{
  require ::ipmi

  validate_string($ip,$netmask,$gateway,$type)
  validate_integer($lan_channel)
  validate_re($type, '^dhcp$|^static$', 'Network type must be either dhcp or static')

  if $type == 'dhcp' {

    exec { "ipmi_set_dhcp_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipsrc dhcp",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 0",
    }
  }

  else {

    exec { "ipmi_set_static_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipsrc static",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 1",
      notify  => [Exec["ipmi_set_ipaddr_${lan_channel}"], Exec["ipmi_set_defgw_\
${lan_channel}"], Exec["ipmi_set_netmask_${lan_channel}"]],
    }

    exec { "ipmi_set_ipaddr_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipaddr ${ip}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'IP Address  ' | sed -e 's/.* : //g')\" != \"${ip}\"",
    }

    exec { "ipmi_set_defgw_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} defgw ipaddr ${gateway}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'Default Gateway IP' | sed -e 's/.* : //g')\" != \"${gateway}\"",
    }

    exec { "ipmi_set_netmask_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} netmask ${netmask}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'Subnet Mask' | sed -e 's/.* : //g')\" != \"${netmask}\"",
    }
  }

  # I'm not sure if this is supported everywhere but going by these documents:
  # http://serverfault.com/questions/361940/configuring-supermicro-ipmi-to-use-one-of-the-lan-interfaces-instead-of-the-ipmi
  # https://asgardahost.org/useful-raw-commands-for-supermicro-ipmi-modules/
  # 
  # They outline that the network interface can be in three states:
  #   0x00 = Dedicated
  #   0x01 = Onboard / Shared
  #   0x02 = Failover
  # With Failover being the default and meaining the BIOS should try Dedicated
  # if it detects teh interface on boot but will fall back to Onboard or 
  # Shared mode where the IPMI controller will use the eth0 interface along
  # with the OS

  $interface_mode_number = 0
  case $interface {
    'dedicated': { $interface_mode_number = 0 }
    'shared': { $interface_mode_number = 1 }
    'failover': { $interface_mode_number = 2 }
  }

  # To add to the fun I can find refernce to two ways of changing it on Supermicro servers:
  #  For older models:
  #    ipmitool raw 0x30 0x70 0x0c 1 1 0
  #
  #  For X9 motherboards:
  #    ipmitool raw 0x30 0x70 0x0c 1 0
  # Would be good to figure out what the real differnce is(hardware or firmware) and add a check.

  exec { "ipmi_set_interface_$interface":
    command => "/usr/bin/ipmitool raw 0x30 0x70 0xc 1 1 $interface_mode_number",
    onlyif  => "/usr/bin/test \"$(ipmitool raw 0x30 0x70 0x0c 0)\" != \"${interface_mode_number}\"",
  }

}
