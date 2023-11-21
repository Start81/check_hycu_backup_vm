#!/usr/bin/perl -w
#=============================================================================== 
# Script Name   : check_hycu_backup_vm.pl
# Usage Syntax  : check_hycu_backup_vm.pl -H <hostname> -p <port>  -u <User> -P <password> -n <vm name>[-w <threshold> ] [-c <threshold> ]  [-t <timeout>] [-U <unit>] [-a <apiversion>] 
# Version       : 1.4.0
# Last Modified : 23/01/2023
# Modified By   : Start81 (DESMAREST JULIEN) 
# Description   : Nagios check that uses HYCUs REST API to get backup status
# Depends On    : REST::Client Data::Dumper Monitoring::Plugin MIME::Base64 JSON LWP::UserAgent Readonly
# 
# Changelog: 
#    Legend: 
#       [*] Informational, [!] Bugfix, [+] Added, [-] Removed 
#  - 11/04/2022| 1.0.0 | [*] First release
#  - 12/04/2022| 1.1.0 | [*] Update to handle multiple uid for one vm
#  - 20/01/2023| 1.3.0 | [*] Autodiscover list only protected vm
#  - 23/01/2023| 1.4.0 | [*] Update improve autodiscover it provide vm name and uid and the script can use uid instead of vm name 
#===============================================================================

use strict;
use warnings;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use Monitoring::Plugin;
use Data::Dumper;
use REST::Client;
use JSON;
use utf8; 
use MIME::Base64;
use LWP::UserAgent;
use Readonly;
use File::Basename;

Readonly our $VERSION => "1.4.0";
Readonly our $page_size => 1000;

my $me = basename($0);
my $o_verb;

sub verb { my $t=shift; print $t,"\n" if ($o_verb) ; return 0}

my $np = Monitoring::Plugin->new(
    usage => "Usage: %s -H <hostname> -p <port>  -u <User> -P <password> -n <vm name> | -i <uid> | -L [-w <threshold> ] [-c <threshold> ]  [-t <timeout>] [-U <unit>] [-a <apiversion>] \n",
    plugin => $me,
    shortname => $me,
    blurb => "$me is a Nagios check that uses HYCUs REST API to get backup status",
    version => $VERSION,
    timeout => 30
);
$np->add_arg(
    spec => 'host|H=s',
    help => "-H, --host=STRING\n"
          . '   Hostname',
    required => 1
);
$np->add_arg(
    spec => 'name|n=s',
    help => "-n, --name=STRING\n"
          . '   vm name',
    required => 0
);
$np->add_arg(
    spec => 'uuid|i=s',
    help => "-i, -'uuid=STRING\n"
          . '   vm uuid',
    required => 0
);
$np->add_arg(
    spec => 'port|p=i',
    help => "-p, --port=INTEGER\n"
          . '  Port Number',
    required => 1,
    default => "8443"
);
$np->add_arg(
    spec => 'apiversion|a=s',
    help => "-a, --apiversion=string\n"
          . '  HYCU API version',
    required => 1,
    default => 'v1.0'
);
$np->add_arg(
    spec => 'user|u=s',
    help => "-u, --user=string\n"
          . '  User name for api authentication',
    required => 1,
);
$np->add_arg(
    spec => 'Password|P=s',
    help => "-P, --Password=string\n"
          . '  User password for api authentication',
    required => 1,
);
$np->add_arg(
    spec => 'ssl|S',
    help => "-S, --ssl\n   The hycu serveur use ssl",
    required => 0
);
$np->add_arg(
    spec => 'warning|w=s',
    help => "-w, --warning=threshold\n" 
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'critical|c=s',
    help => "-c, --critical=threshold\n"  
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'unit|U=s',
    help => "-u, --unit=unit\n"  
          . '   Unit are m|h|d for minutes|hours|day',

);
$np->add_arg(
    spec => 'listvms|L',
    help => "-L, --listvms\n"  
          . '   Autodiscover protected vm list',

);

$np->getopts;

my $o_host = $np->opts->host;
my $o_login = $np->opts->user;
my $o_pwd = $np->opts->Password;
my $o_apiversion = $np->opts->apiversion;
my $o_port = $np->opts->port;
my $o_name = $np->opts->name;
my $o_use_ssl = 0;
my $o_list_vms = $np->opts->listvms;
my $o_uuid = $np->opts->uuid;
$o_use_ssl = $np->opts->ssl if (defined $np->opts->ssl);
$o_verb = $np->opts->verbose;
my $o_warning = $np->opts->warning;
my $o_critical = $np->opts->critical;
my $page = 1; #Current page when getting vm list 
my $vms_count = 0 ;
my $total_vms_count = 0;
my $o_timeout = $np->opts->timeout;
my $unit = $np->opts->unit;
my $uid;

#Check parameters
if ((!$o_list_vms) && (!$o_name) && (!$o_uuid)) {
    $np->plugin_die("Vm name or uuid missing");
}
if (!$unit){
    $unit = "d"
}
if ($o_timeout > 60){
    $np->plugin_die("Invalid time-out");
}

#Rest client Init
my $client = REST::Client->new();
$client->setTimeout($o_timeout);
my $url = "http://";
$client->addHeader('Content-Type', 'application/json;charset=utf8');
$client->addHeader('Accept', 'application/json');
$client->addHeader('Accept-Encoding',"gzip, deflate, br");
if ($o_use_ssl) {
    my $ua = LWP::UserAgent->new(
        timeout  => $o_timeout,
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => SSL_VERIFY_NONE
        },
    );
    $url = "https://";
    $client->setUseragent($ua);
}

#Add authentication
$client->addHeader('Authorization', 'Basic ' . encode_base64("$o_login:$o_pwd"));
#If no uuid then get protected vm list
if (!$o_uuid){
    $url = "$url$o_host:$o_port/rest/$o_apiversion/vms?pageSize=$page_size&pageNumber=";
    my $current_url;
    my %vms;
    my $i;
    my $vm;

    do{
        $current_url="$url$page";
        verb($current_url);
        $client->GET($current_url);
        if($client->responseCode() ne '200'){
            $np->plugin_exit('UNKNOWN', " response code : " . $client->responseCode() . " Message : Error when getting vm list". $client->{_res}->decoded_content );
        }
        my $rep = $client->{_res}->decoded_content;
        my $vm_list_json = from_json($rep);
        if ($total_vms_count == 0){
            $total_vms_count = $vm_list_json->{'metadata'}->{'totalEntityCount'} ;
            verb("Total Vm count : $total_vms_count\n");
        }
        $vms_count = $vms_count  + $vm_list_json->{'metadata'}->{'entityCount'};
        verb("nb vm already read : $vms_count\n");
        $i = 0;
        while (exists ($vm_list_json->{'entities'}->[$i])){
            $vm = q{};
            $uid = q{};
            $vm = $vm_list_json->{'entities'}->[$i]->{'vmName'};
            $uid = $vm_list_json->{'entities'}->[$i]->{'uuid'}; 
            if ($vm_list_json->{'entities'}->[$i]->{'status'} eq 'PROTECTED' ){
                $vms{$vm}=$uid;
            }
            $i++;
        }
        $page++;
    } while ( $vms_count < $total_vms_count);
    

    my @keys = keys %vms;
    my $size;
    $size = @keys;
    verb ("hash size : $size\n");
    if (!$o_list_vms){
        #If vm name not found
        if (!defined($vms{$o_name})) {
            my $list="";
            my $key ="";
            #format a vm list
            foreach my $key (@keys) {
                $list = "$list $key" 

            }
            $np->plugin_exit('UNKNOWN',"vm $o_name not found the vm list is $list"  );
        }
    } else {
        #Format autodiscover Xml for centreon
        my $xml='<?xml version="1.0" encoding="utf-8"?><data>'."\n";
        foreach my $key (@keys) {
            $xml = $xml . '<label name="' . $key . '"uuid="'. $vms{$key} . '"/>' . "\n"; 
        }
        $xml = $xml . "</data>\n";
        print $xml;
        exit 0;
    }
    # inject uuid in api url
    verb ("Found uuid : $vms{$o_name}\n");
    $uid = $vms{$o_name};
};

$uid = $o_uuid if (!$uid);
verb ("uid = $uid\n");

my $apiurlbackup ;
my $rep_backup;
my $backup_list_json;
my $total_vm_backup;
my $last_backup;
my @criticals = ();
my @warnings = ();
my @unknown = ();
my $msg = "";
my %backup;

$apiurlbackup = 'http://';
$apiurlbackup = 'https://' if ($o_use_ssl) ;
$apiurlbackup = "$apiurlbackup$o_host:$o_port/rest/$o_apiversion/vms/$uid/backups?pageNumber=1";
verb($apiurlbackup);
$client->GET($apiurlbackup);
if($client->responseCode() ne '200'){
    $np->plugin_exit(UNKNOWN, " response code : " . $client->responseCode() . " Message : Error when getting backup list". $client->{_res}->decoded_content );
}
$rep_backup = $client->{_res}->decoded_content;
$backup_list_json = from_json($rep_backup);
#verb(Dumper($backup_list_json));
$total_vm_backup = $backup_list_json->{'metadata'}->{'grandTotalEntityCount'};
verb ("Found $total_vm_backup Backup(s)\n");
if ($total_vm_backup == 0) {
    push(@unknown, "No Backup found for VM $o_name $uid");
} else {
    $last_backup = $backup_list_json->{'entities'}->[0];
    verb(Dumper($last_backup));

    $backup{'status'} = $last_backup->{'status'};
    $backup{'compliancy'} = $last_backup->{'compliancy'};
    $backup{'type'} = $last_backup->{'type'};
    $backup{'modified'} = ($last_backup->{'common'}->{'modified'})/1000;
    $backup{'expiration'} = $last_backup->{'backup_expiration'};
    $backup{'vmName'} = $last_backup->{'vmName'};

    #Affichage de la table de hachage
    if ($o_verb) {
        my $key;
        my $value;
        while (($key, $value) = each (%backup))
        {
          $value = $backup{$key};
          print "  $key => $value\n";
        }
    }

    #['RUNNING', 'FATAL', 'OK', 'EXPIRED', 'ERROR', 'WARNING', 'SKIPPED']
    push( @criticals, "last backup status for vm $backup{'vmName'} uid = $uid is $backup{'status'} type $backup{'type'} ") if (($backup{'status'} eq 'ERROR')|| ($backup{'status'} eq 'FATAL')||($backup{'status'} eq 'EXPIRED'));
    push (@warnings ,"last backup status for vm $backup{'vmName'} uid = $uid is $backup{'status'} type $backup{'type'} ") if (($backup{'status'} eq 'SKIPPED')|| ($backup{'status'} eq 'WARNING'));
    my $epoc = time();
    verb ("$epoc - $backup{'modified'}");
    my $date_diff =  $epoc - $backup{'modified'};
    verb ("date_diff $date_diff\n");
    my $result = 0;
    if ($date_diff != 0) {
        if ($unit eq 'd') {
            $result = $date_diff/(86400);
        } elsif($unit eq 'm') {
            $result = $date_diff/60;
        } elsif($unit eq 'h'){
            $result = $date_diff/3600 ;
        } else {
            $np->plugin_exit('UNKNOWN', "unit must be m|h|d for minutes|hours|day")
        }
    } 
    print "Age : $result \n" if $o_verb ;
    $result = substr($result ,0,5);
    $np->add_perfdata(label => "backup_age_$uid", value => $result, uom => $unit, warning => $o_warning, critical => $o_critical);
    if ((defined($np->opts->warning) || defined($np->opts->critical))) {
        $np->set_thresholds(warning => $o_warning, critical => $o_critical);
        my $status = $np->check_threshold($result);
        push( @criticals, "last backup for vm $backup{'vmName'} uid = $uid is too old backup age is $result $unit") if ($status==2);
        push( @warnings, "last backup  for vm $backup{'vmName'} uid = $uid is too old backup age is $result $unit") if ($status==1);
    } 
    $msg = "$msg last backup status for vm $backup{'vmName'} uid = $uid is $backup{'status'} type $backup{'type'} ";
}
$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('UNKNOWN', join(', ', @unknown)) if (scalar @unknown > 0);
$np->plugin_exit('OK', $msg );
