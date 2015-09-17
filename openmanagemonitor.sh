#!/bin/bash

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Company name - Division name - Project name
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# HallOfTips - 04/05/2012 - HardChk.bash - 1.8
# ---------------------------------
# This script use the dell omreport & omconfig to check hardware status
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#####################################
##### HOW-TO
#####################################
# This script print its results to a text file ($TmpFile), that is either sent as an email (default behaviour) or printed to stdout (using the "-p" option).
#+ It could also clear given logs with the "-c <log_name>" option
#
# Each hardware components status are retrieved using the omreport dell utility, for each hardware component the status might of 4 kind :
#   1 - Ok           = The component is in perfect condition
#   2 - Non-Critical = The component is NOT in perfect condition but is also not about to fail
#   3 - Critical     = The component might be about to fail, you should fix the reported problem ASAP !
#   4 - Not found    = The component was not found, this is the standard behaviour from the omreport utility

#####################################
##### TODO
#####################################

#####################################
##### ChangeLog
#####################################

###### V1.8 (30/07/12)
# - Modded most of the shitty construct ""while read" +"echo line" + "read $line""
# - Added tac command to reverse the log display

###### V1.7 (25/07/12)
# - Added BIOS settings check (Maximum Performance as power management profile)
# - Added CPU settings check (Turbo Mode & HyperThreading)

###### V1.6 (29/06/12)
# - Added "ESMLOG" domain (check the esmlog)

###### V1.5 (25/06/12)
# - Added "-c" option (clear logs)

###### V1.4 (14/06/12)
# - Added "-p" option for local mode : this mode print out the results AND send the email (This needs to be changed, there is no need to send the email in this mode)
# - Added the Usage function
# - Minor bug corrected (for level_4 cmd)

###### V1.3 (08/06/12)
# - Added ${Serial_number} to SystemInfo() + changed from echo to cat <<HEREDOC

###### V1.2 (11/05/12)
# - Added Email object matching the worst status (Ok, Non-Critical, Critical)

###### V1.1 (10/05/12)
# - Added server model + OS version to email body

#####################################
##### VARIABLES
#####################################

PATH=$PATH:/usr/bin:/opt/dell/srvadmin/bin/
export PATH

ADMIN="user@company.fr"
ESMAGE=48
# ADMIN="jonathan.bayer@achieve3000.com"

Local_mode="0"
Fatal_Error="66"
E_OPTERROR="42"
Network_file="/etc/sysconfig/network-scripts/ifcfg-eth0"
OsRelease=$(cat /etc/redhat-release)
Ip_address=$(grep "IPADDR=" "${Network_file}" |cut -d"=" -f2)
TmpDir="/tmp"
TmpFile="${TmpDir}/HardChk_EMAIL_${HostName}_$(date +%Y-%m-%d)_$$"
NonCritical="2"
Critical="3"
OkMsg="Nothing to report"
NonCriticalMsg=" - Warning : At least one components status is \"Non-Critical\" - "
CriticalMsg="=== FAILURE : At least one components status is \"Critical\" ! ==="
err=0
PRINT_OK=0
DomainEnd="~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
RETCODE="0"

warnings=0
failures=0

MAILHOST="mailhost.company.fr"
MAILHOST="NaviSite.com.s5b2.psmtp.com"
MAILHOST="localhost"

#####################################
##### USAGE
#####################################

# usage & examples
Usage() {
  cat <<EOF
Usage: $(basename $0) [-phco] [-a] <IP>

Options :
          -p : print output to stdout
          -h : print this message (help)
          -c : clear IML given as parameter
          -a : Specify address(s) to send report to
          -o : Print OK/Not Ok depending on status, send mail only if not ok

Examples:
          1) To check one server hardware state and send the results to the administrator (currently $ADMIN) : "$(basename $0)"
          2) To check one server hardware state and print the results to stdout (screen) : "$(basename $0) -p"
EOF
  exit $E_OPTERROR
}

#####################################
##### PRIMARY FUNCTIONS
#####################################

# This function is used to clear logs
Log_Clear() {
  # Clear HP Integrated Management Log
  hpasmcli -s "SHOW IML" > /var/log/hpiml.archive_$(date +%Y-%m-%d)
  hpasmcli -s "CLEAR IML"
}

#####################################
##### OPTION MANAGEMENT
#####################################

# Process options analysis
while getopts ":onphca:e:" Option ; do
# Declaration initiale.
# Le ":" apr s l'option 'c' montre qu'il y aura un argument associ  : $OPTARG
# The ":" after s option 'c' shows that there will be associated argument: $ OPTARG
# le ":" en premiere position defini (peut-etre, a verifier) que le cas "*" est g r  par nous ou l'inverse, encore une fois c'est a verifier
# the ":" in the first position defined (perhaps, a check) that if "*" is managed by us or the reverse, again this is a check

  case $Option in
    p ) Local_mode="1" && echo "-> Local mode is activated : all results will be printed on stdout" # Send $TmpFile to STDOUT
    ;;
    n ) Local_mode="2" ;; # Only print sum of warnings & failures
    c ) Log_Clear
    ;;
    h ) Usage && exit $E_OPTERROR
    ;;
    a ) ADMIN=${OPTARG}
    ;;
    e ) ESMAGE=${OPTARG}
        ESMAGE=$((ESMAGE * 3600))
    ;;
    o ) PRINT_OK=1
    ;;
    \? ) echo "Invalid option: -$OPTARG" >&2 && Usage && exit $E_OPTERROR # this handle the "invalid option" case
    ;;
    : ) echo "Option -${OPTARG} requires an argument (\"$(echo ${Logs_names[@]})\")" >&2 && Usage && exit $E_OPTERROR # this handle the "invalid parameter for this option" case
    ;;
  esac
done

#####################################
##### FUNCTIONS
#####################################

# The cleaning function cleans everything after the script is terminated, either for regular termination or interruption. It is called by the trap command
Cleaning() {
 echo "Cleaning before exiting..."
 rm -f ${TmpFile}
 exit 0
}

# This is the function that print AND log any errors occuring during $0 execution: print $1 on screen AND print $2 (the message) in $ErrorLog)
# ErrorPrintandlog () {
# if [[ "${1}" = "${F_Error}" ]] ; then
#   echo  "=> FATAL_ERROR, exiting (see ${ErrorLog} for more infos)" && echo "${2}" >> ${ErrorLog} && exit ${F_Error}
# elif [[ "${1}" = "${Error}" ]] ; then
#   echo  "=> ERROR (see ${ErrorLog} for more infos)" && echo "${2}" >> ${ErrorLog}
# fi
# }

# Generate the ${TmpFile} header
MailHeader() {
  echo "This is an automatically generated email by \"$0\" from \"${HOSTNAME}\" (on $(date +%d-%m-%Y)" @ $(date +%H:%M)\) >> ${TmpFile}
}

# Generate the ${TmpFile} footer
MailFooter() {
  echo -e "\n\n--> For more information you should check the Dell Open Manage web interface (using this command : \"firefox https://${Ip_address}:1311\" )" >> ${TmpFile}
}

# Generate the email "object field" according to the worst status of checked components
AddToMailObject() {
# (Return code = 2) : "non-Critical" status only ;
#+ (Return code = 3) : at least- 1 "Critical" status
  ReturnCode="${1}"
  if [[ "${ReturnCode}" = "0" ]] ; then
    MailObject=$( echo "[MONITORING] $HOSTNAME : ${OkMsg} " )
  elif [[ "${ReturnCode}" = "2" ]] ; then
    MailObject=$( echo -e "[MONITORING] $HOSTNAME : ${NonCriticalMsg} " )
    err=1
  elif [[ "${ReturnCode}" = "3" ]] ; then
    MailObject=$( echo -e "[MONITORING] $HOSTNAME : ${CriticalMsg} " )
    err=1
  fi
}

# Print domain name before domain information
PrintDomainStart() {
  Domain="${1}"
  DomainStart="\n~~~~~~~~~~~ ${Domain} ~~~~~~~~~~~\n"
  echo -e "${DomainStart}" >> ${TmpFile}
}

# Print a "new line" character at the end of a domain field
PrintDomainEnd() {
  DomainStart="\n"
# JBB
  echo -e "${DomainStart}" >> ${TmpFile}
}

# Print an "[Ok]" message with the component name
PrintOk() {
  # Usage: $0 called with the "system_name" as $1, its "status" as $2 and the "Logs" flag as $3
  Component="${1}"
  Status="${2}"
  Logs="${3}"
  if [[ "${Logs}" = "1" ]] ; then tab="-50" ; else tab="-25"; fi # If $0 is used to print a Log_Chk() result
                                                                #+ then the "Logs" flag is active and the formatting is different
  printf  -- "- %"${tab}"s --------------> [%s]\n" "[${Component}]" "$Status" >> ${TmpFile}
}

# Print the component name and infos : This is used for example if a component does not exists
PrintInfos() {
  # Usage: $0 called with the "system_name" as $1, its "status" as $2 and the "Logs" flag as $3
  Component="${1}"
  Status="${2}"
  Logs="${3}"
  if [[ "${Logs}" = "1" ]] ; then tab="-50" ; else tab="-25"; fi
  printf  -- "- %"${tab}"s --------------> [%s]\n" "[${Component}]" "$Status" >> ${TmpFile}
}

# Print a "[Non-Critical]" message with the component name
PrintWarning() {
  # Usage: $0 called with the "system_name" as $1, its "status" as $2 and the "Logs" flag as $3
  Component="${1}"
  Status="${2}"
  Logs="${3}"
  if [[ "${Logs}" = "1" ]] ; then tab="-50" ; else tab="-25"; fi
  printf  -- "- %"${tab}"s --------------> [%s]\n" "[${Component}]" "$Status" >> ${TmpFile}
  warnings=$((warnings + 1))
}

# Print a "[Critical]" message with the component name
PrintFailure() {
  # Usage: $0 called with the "system_name" as $1, its "status" as $2 and the "Logs" flag as $3
  Component="${1}"
  Status="${2}"
  Logs="${3}"
  if [[ "${Logs}" = "1" ]] ; then tab="-50" ; else tab="-25"; fi
  printf  -- "- %"${tab}"s --------------> [%s] <----------\n" "[${Component}]" "$Status" >> ${TmpFile}
  printf  -- "- %"${tab}"s --------------> [%s] <----------\n" "[${Component}]" "$Status"
  failures=$((failures + 1))
}

# Print some information about the tested machine
SystemInfo() {
  DOMAIN="INFORMATION"
  PrintDomainStart ${DOMAIN}

  # Product Name + Serial Number :
  while IFS=":" read Description data ; do
	  PrintInfos "${Description// }" "${data# }"
	  if [[ "${Description}" =~ "System" || "Serial" ]] ; then
		  echo "${data# }"
 	  fi
  done <<<"$(hpasmcli -s "SHOW SERVER" | awk '/^System/||/^Serial/')"

  # OS version :
  os=$(cut -d " " -f -5 /etc/redhat-release)
  release=$(cut -d " " -f 6- /etc/redhat-release)
  kernel=$(uname -r| cut -d \. -f -4)
  arch=$(uname -r| awk -F \. '{print "("$5")"}')

  PrintInfos "OperatingSystem" "${os}"
  PrintInfos "OperatingSystemVersion" "${release} Kernel ${kernel} ${arch}"
  PrintInfos "SystemTime" "$(date)"
  PrintInfos "SystemBootupTime" "$(who -b|cut -d " " -f 13-)"

}

# Function to check "system" components (see omreport -? for more info about what are "system" components)
System_Chk() {
  DOMAIN="SYSTEM"
  PrintDomainStart ${DOMAIN}
  # overall health status retrieving
  while IFS=": " read Status Name ; do
    if [[ "${Status}" =~ 'Ok' ]] ; then
      PrintOk "${Name}" "${Status}"
    elif [[ "${Status}" =~ 'Non-Critical' ]] ; then
      PrintWarning "${Name}" "${Status}" && RETCODE="${NonCritical}" 2>/dev/null
    elif [[ "${Status}" =~ 'Critical' ]] ; then
      PrintFailure "${Name}" "${Status}" && declare -r RETCODE="${Critical}"
    else
    # This might be used when a device does not exist (such as batteries for PERC H200 controller), this print out an info but does NOT set the error code
    PrintInfos "${level3}_${count}" "${bin1} ${Level3_Status}"
    fi
  done <<<"$(omreport system |grep -E "^(Ok|Critical|Non-Critical)")"
  PrintDomainEnd
  return $RETCODE
}

# Function to check "chassis" components (see omreport -? for more info about what are "chassis" components)
Chassis_Chk() {
  DOMAIN="CHASSIS"
  PrintDomainStart ${DOMAIN}

  # launch the command that retrieve the chassis components status and append it to the EMAIL temp file
  while IFS=": " read Status Name ; do
    if [[ "${Status}" =~ 'Ok' ]] ; then
      PrintOk "${Name}" "${Status}"
    elif [[ "${Status}" =~ 'Non-Critical' ]] ; then
      PrintWarning "${Name}" "${Status}" && RETCODE="${NonCritical}" 2>/dev/null
    elif [[ "${Status}" =~ 'Critical' ]] ; then
      PrintFailure "${Name}" "${Status}" && declare -r RETCODE="${Critical}"
    else
    PrintInfos "${level3}_${count}" "${bin1} ${Level3_Status }"
    fi
  done <<EOF
            $(omreport chassis |grep -E '^(Ok|Critical|Non-Critical)')
EOF

  PrintDomainEnd
  return $RETCODE
}

# Function to check "storage" components (see hpssacli for more info about what are "storage" components)
Storage_Chk() {
  DOMAIN="STORAGE"
  PrintDomainStart ${DOMAIN}

  # Check status of Controller(s), Cache, and Battery
  while IFS=": " read bin1 bin2 status ; do 
    PrintOk "${bin1}" "${status}"
  done <<<"$(hpssacli ctrl all show status | awk '/Controller/ || /Cache/ || /Battery/')"

  # Check status of logical drives
  while IFS=", ()" read ldrive ldnum oparen size raid rlevel status cparen ; do
    PrintOk "${ldrive} ${ldnum}" "${status}"
  done <<<"$(hpssacli ctrl all show config | awk '/logicaldrive/')"

  # Check status of physical drives
  while IFS=", ()" read pdrive location oparen port box bay baynum type size status cparen ; do
    PrintOk "${pdrive} ${location}" "${status}"
  done <<<"$(hpssacli ctrl all show config | awk '/physicaldrive/')"

  PrintDomainEnd
}

# This checks Integrated Management Logs contents
Log_Chk() {
  DOMAIN="IML"
  PrintDomainStart ${DOMAIN}

  while IFS=":" read Status Type Description ; do

    if [[ "${Status}" = 'CRITICAL' ]] ; then
      PrintFailure "${Description:0:24}... @ ${Data_or_Date#[[:upper:]][[:alpha:]][[:alpha:]][[:space:]]}" "${Status}" "1" && declare -r RETCODE="${Critical}" 2>/dev/null
    elif [[ "${Status}" = 'CAUTION' ]] ; then
      PrintWarning "${Description:0:24}... @ ${Data_or_Date#[[:upper:]][[:alpha:]][[:alpha:]][[:space:]]}" "${Status}" "1" && RETCODE="${NonCritical}" 2>/dev/null
    elif [[ "${Status}" = 'INFO' ]] ; then
      PrintOk "${Description:0:24}... @ ${Data_or_Date#[[:upper:]][[:alpha:]][[:alpha:]][[:space:]]}" "${Status}" "1"
    fi
  done <<<"$(hpasmcli -s "SHOW IML")"

  Log_Clear

  PrintDomainEnd
  return $RETCODE
}

# This checks Bios settings
Bios_Chk() {
  # Usage: $0
  DOMAIN="BIOS"
  PrintDomainStart ${DOMAIN}

  # Check if HyperThreading is enabled.
  ht=S(hpasmcli -s "SHOW HT" | awk '/enabled/ {print $5}')
  if [[ $ht =~ "enabled" ]] ; then
    PrintInfos "HyperThreading" "enabled"
  else
    PrintInfos "HyperThreading" "disabled"
  fi

  PrintDomainEnd
  return $RETCODE
}

# Print (using cat) the informations generated by this script (which are also redirected to ${TmpFile}) on the stdout
Print_on_screen() {
  cat ${TmpFile}
  echo ""
}

# Send the content of ${TmpFile} via email (only works at CORYS for now)
SendMail() {
  # generating the Email content
  EMAIL=$(cat ${TmpFile})
ncbin=`which nc`
if [ "$ncbin" = "" ]; then
  mail -s "${MailObject}" $ADMIN <${TmpFile}
else
nc -v ${MAILHOST} 25 1>/dev/null << EOF
ehlo $HOSTNAME
mail from: $HOSTNAME
rcpt to: $ADMIN
data
From: $HOSTNAME
To: $ADMIN
Subject: ${MailObject}
${EMAIL}
.
quit
EOF
fi
}

#####################################
##### MAIN
#####################################

# Cleaning before anything else
rm -f ${TmpDir}/HardChk_EMAIL*

# hpasmcli command must be available
if ! ( which hpasmcli ) &>/dev/null ; then
  echo "hpasmcli command not found : please make sure you are on a server and hpasmcli is installed, exiting ..." && exit $Fatal_Error
fi

# Set the trap command that will call the Cleaning function in any termination cases
trap "Cleaning" SIGHUP SIGINT SIGTERM SIGKILL

# generating the Email header
MailHeader

#Printing server information
read ChassisModel <<< "$(SystemInfo)"

# Start checking all status :

## System
System_Chk
RETCODE="${?}"

## Chassis
Chassis_Chk
RETCODE="${?}"

## Storage
Storage_Chk
RETCODE="${?}"

## Bios
Bios_Chk
RETCODE="${?}"

## Logs
Log_Chk
RETCODE="${?}"

# Generating the Mail object based upon the "worst" RETCODE
AddToMailObject "${RETCODE}"

# Generating the Email footer
MailFooter

# then we finally send the Email or print outuput on screen if the "--print" (or "-p") flag is active
if [[ "${Local_mode}" = "1" ]] ; then
    Print_on_screen
elif [[ "${Local_mode}" = "0" ]] ; then
    if [ $PRINT_OK -eq 1 ]; then
        if [ $err -ne 0 ]; then
	    SendMail
	    echo "Not OK"
	else
	    echo "OK"
        fi
    else
	SendMail
    fi
elif [[ "${Local_mode}" = "2" ]] ; then
	n=$((warnings + errors))
	echo $n
else
    exit $Fatal_Error
fi
