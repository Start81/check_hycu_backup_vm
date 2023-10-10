## check_hycu_backup_vm

Nagios check that uses HYCU's REST API to get backup status

### prerequisites

This script uses theses libs : 
REST::Client, Data::Dumper, Monitoring::Plugin, MIME::Base64, JSON, LWP::UserAgent, Readonly

to install them type ::

```
sudo cpan REST::Client Data::Dumper Monitoring::Plugin MIME::Base64 JSON LWP::UserAgent Readonly
```

### Use case

```bash
check_hycu_backup.pl 1.4.0

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

check_hycu_backup_vm is a Nagios check that uses HYCUs REST API to get backup status

Usage: check_hycu_backup.pl -H <hostname> -p <port>  -u <User> -P <password> -n <vm name> | -i <uuid> | -L [-w <threshold> ] [-c <threshold> ]  [-t <timeout>] [-U <unit>] [-a <apiversion>]

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -H, --host=STRING
   Hostname
 -n, --name=STRING
   vm name
 -i, --uuid=STRING
   vm uuid
 -p, --port=INTEGER
  Port Number
 -a, --apiversion=string
  HYCU API version
 -u, --user=string
  User name for api authentication
 -P, --Password=string
  User password for api authentication
 -S, --ssl
   The hycu serveur use ssl
 -w, --warning=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -c, --critical=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -u, --unit=unit
   Unit are m|h|d for minutes|hours|day
 -L, --listvms
   Autodiscover proteted vm list
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 30)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```

sample :

```bash
./check_hycu_nagios.pl -H MyHYCUserver --ssl -p 8443 -a v1.0 -n MyvmToBackup  -u user@domain -P password  -U d -c 2 -w 1
#OR
./check_hycu_nagios.pl -H MyHYCUserver --ssl -p 8443 -a v1.0 -i xxxxxxxx-xxxx-xxxx-xxxx-xxxxxx  -u user@domain -P password  -U d -c 2 -w 1

./check_hycu_nagios.pl -H MyHYCUserver --ssl -p 8443 -a v1.0 -n wtf  -u user@domain -P password  -U d -c 2 -w 1
```

you may get :

```bash
check_hycu_vm OK -  last backup status for vm MyVM uid = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxx is OK type INCREMENTAL_BACKUP  | backup_age_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxx=0.240d;1;2

check_hycu_vm UNKNOWN - UNKNOWN vm wtf not found the vm list is  MyVm1 MyVm2 MyVm3...
```
