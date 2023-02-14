#!/bin/bash -u
#----------------------------------------------------------
#     Synopsis: email_calendar [-hv]
#               --url <Google_Calendar_URL> or
#               --file <Path_to_local_ics_file>
#
#  Description: sends the entries of a Google Calendar
#               as an email, also works with local .ics files
#     Language: bash script
#       Author: heckerya78723@th-nuernberg.de
#----------------------------------------------------------

# Default values
helpText=$(sed -ne '1,/#\-\-\-\-\-/d;/#\-\-\-\-\-/q;s/^# //p' "$0")
verboseMode=0
inputFile=""
calendarURL=""
storageDir="${HOME}/.gcal"
calendarFile=""

# Internal variables
scriptName=$(basename "${0%.*sh}")

while [[ "${1-}" =~ ^- ]]; do
    case "$1" in
        -h | --help)    echo "$helpText" ; exit 0 ;;
        -v | --verbose) verboseMode=1 ;;
        --file)         inputFile=${2} ; shift ;;
        --url)          calendarURL=${2} ; shift ;;
        *)              echo "Invalid option '$1'" >&2 ; exit 1 ;;
    esac
    shift
done

function printVerbose ()
# DESCRIPTION: Prints text only in verbose mode
# PARAMETER:   Verbose text
# STDOUT:      TEXT in verbose mode
{
    if [[ verboseMode -eq 1 ]] ; then
        echo "[INFO] ${scriptName}: $1"
    fi
    return 0
}

function printError ()
# DESCRIPTION: Prints an error text to stderr
# PARAMETER:   Error text
# STDERR:      Error text
{
    echo "[ERROR] ${scriptName}: $1" >&2
    exit 1
}

function getDateDiff ()
# DESCRIPTION: calculates the difference between two dates in days
# PARAMETER:   $1 start date, $2 end date in YYYYMMDD format
# STDOUT:      days as integer
{
    local date1
    local date2
    date1=$(date -d "$1" +%s)
    date2=$(date -d "$2" +%s)
    # transformation from seconds to days: 1 day = 24*60*60 = 86400
    echo "$(( (date2 - date1) / 86400 ))"
}

function convert_utc_to_local_time() 
# DESCRIPTION: converts a UTC time to the local time
# PARAMETER:   $1 start date, $2 start time in YYYYMMDD and HHMM format
# STDOUT:      local date and time in YYYYMMDD and HHMM format 
{
    local start_date=$1
    local start_time=$2
    local start_datetime="${start_date:0:4}-${start_date:4:2}-${start_date:6:2} ${start_time:0:2}:${start_time:2:2} UTC"

    local local_datetime=$(TZ=$(date +%Z) date -d "$start_datetime")

    local local_date=$(date -d "$local_datetime" +"%Y%m%d")
    local local_time=$(date -d "$local_datetime" +"%H%M")
    echo "$local_date $local_time"
}

# Prevent --file and --url options are specified
if [[ -n ${calendarURL} && -n ${inputFile} ]]; then
    printError "Only one calendar option can be choosen"
fi

# Prevent no calendar option is given
if [[ -z ${calendarURL} && -z ${inputFile} ]]; then
    printError "Please specify at least one calendar option"
fi

# Check if calendar file is a valid ics file
if [[ -n ${inputFile} ]]; then
    printVerbose "Calender file: ${inputFile}"
    if [[ ! -f ${inputFile} ]]; then
        printError "File ${inputFile} does not exist"
    fi

    printVerbose "Calendar file ending: ${inputFile##*.}"
    if [[ ${inputFile##*.} != "ics" ]]; then
        printError "File ${inputFile} is not a valid ics file"
    fi
    calendarFile=${inputFile}
fi


# Downloading calendar to $storageDir
if [[ -n ${calendarURL} ]]; then
    printVerbose "Calender URL: ${calendarURL}"
    calendarURLName=${calendarURL##*/}
    calendarURLExtension=${calendarURL##*.}
    printVerbose "Calendar name from URL: ${calendarURLName}"

    if [[ ${calendarURLExtension} != "ics" ]]; then
       printError "Not a valid URL, must end with '.ics'"
    fi

    if [[ ! -d ${storageDir} ]]; then
        printVerbose "Creating directory ${storageDir}"
        mkdir "${storageDir}"
    fi
    cd "${storageDir}" || exit

    printVerbose "Starting to download the calendar"
   #if [[ ${verboseMode} -ne 0 ]]; then
       #wget -v -t 2 --timeout 5 --timestamping "${calendarURL}" -o output_wget.log
   #else
       #wget -t 2 --timeout 5 --timestamping "${calendarURL}" -o /dev/null
   #fi

    #Error if the ics file was not downloaded
    if [[ ! -f ${calendarURLName} ]]; then
        printError "Failed to download calendar. Run in verbose mode (-v) and check output log (${storageDir})"
    fi
    calendarFile=${calendarURLName}
fi

# Double checking if the used calendarFile exists, should not reach this line
printVerbose "Parsing the following file: ${calendarFile}"
if [[ ! -f ${calendarFile} ]]; then
    printError "There is no valid calendar file to parse"
fi

# Copies every match as "START;<TIME>;END;<TIME>;DESCRIPTION" in an array "appointments"
# There are two possiblities to create an event:
# 1. with times specified e.g. 02.12.2022 17:30-19:30, in ics file: DTSTART:20221202T173000Z DTEND:20221202T193000Z
# 2. FULL day mode: 02.12.2022 (full day), in ics file: DTSTART;VALUE=DATE:20221202 DTEND;VALUE=DATE:20221203
# In FULL day mode the times are empty
appointments=()
event_block=0
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | tr -d '\r')
    if [[ $line == "BEGIN:VEVENT" ]]; then
        event_block=1
    elif [[ $line == "END:VEVENT" ]]; then
        # check if time is not empty and convert date and time from UTC to local time
        if [[ -n $start_time && -n $end_time ]]; then
            start_date_time=$(convert_utc_to_local_time "$start_date" "$start_time")
            start_date=$(echo "$start_date_time" | awk '{print $1}')
            start_time=$(echo "$start_date_time" | awk '{print $2}')
            end_date_time=$(convert_utc_to_local_time "$end_date" "$end_time")
            end_date=$(echo "$end_date_time" | awk '{print $1}')
            end_time=$(echo "$end_date_time" | awk '{print $2}')
        fi
        event_block=0
        appointments+=("$start_date;$start_time;$end_date;$end_time;$description")
        start_date=''
        start_time=''
        end_date=''
        end_time=''
        description=''
    elif [[ $event_block -eq 1 ]]; then
        if [[ $line == DTSTART* ]]; then
            start_date=$(echo "$line" | awk -F ':' '{print $2}' | awk -F 'T' '{print $1}')
            start_time=$(echo "$line" | awk -F ':' '{print $2}' | awk -F 'T' '{print $2}' | sed 's/00Z$//')
        elif [[ $line == DTEND* ]]; then
            end_date=$(echo "$line" | awk -F ':' '{print $2}' | awk -F 'T' '{print $1}')
            end_time=$(echo "$line" | awk -F ':' '{print $2}' | awk -F 'T' '{print $2}' | sed 's/00Z$//')
        elif [[ $line == SUMMARY* ]]; then
            description=$(echo "$line" | awk -F ':' '{print $2}')
        fi
    fi
done <"${calendarFile}"

today="$(date +'%Y%m%d')"
result=()

# Loop through all appointments and check if they span multiple days
# Depending whether a time is given the output is formatted differently
for ((i = 0; i < ${#appointments[@]}; i++)); do
    currentMatch="${appointments[i]}"
    
    dateStart="$( echo "${currentMatch}" | cut -d \; --field 1 )"
    dateEnd="$( echo "${currentMatch}" | cut -d \; --field 3 )"
    timeStart="$( echo "${currentMatch}" | cut -d \; --field 2 )"
    timeEnd="$( echo "${currentMatch}" | cut -d \; --field 4 )"
    desc="$( echo "${currentMatch}" | cut -d \; --field 5 )"

    multipleDays=0     # if the appointment spans multiple days the amount of days is also printed
    amountOfDays=$(getDateDiff "$dateStart" "$dateEnd")

    # Checks the full day mode without times
    if [[ -z ${timeStart} && -z ${timeEnd} ]] ; then
        [[ ${amountOfDays} -gt 1 ]] && multipleDays=1
        #GCalendar stores the date-end as the next day in full-day mode, therefore it needs to be less (lt)
        if [[ ${today} -ge ${dateStart} && ${today} -lt ${dateEnd} ]]; then
            resultString="- ${desc}"
            [[ ${multipleDays} -eq 1 ]] && resultString+=" (${amountOfDays} days)"
            result+=( "${resultString}" )
        fi
    # Checks the normal mode considering an appointment can be over multiple days
    else
        [[ ${amountOfDays} -gt 0 ]] && multipleDays=1
        if [[ ${today} -ge ${dateStart} && ${today} -le ${dateEnd} ]] ; then
            resultString=$( perl -nE 'say "- $1:$2-$3:$4 | $5" if
            m%\d{8};(\d{2})(\d{2});\d{8};(\d{2})(\d{2});([^\r\n]*)
            %gx' <<< "${currentMatch}")
            [[ ${multipleDays} -eq 1 ]] && resultString+=" ($(( amountOfDays + 1)) days)"
            result+=( "${resultString}" )
        fi
    fi

done

printf "\n---------RESULT -------------%s\n" "${today}"
echo "${result[@]}"

function ifEmptyReplaceWithDefault ()
# DESCRIPTION: checks if read input is empty and replaces it with default
# PARAMETER:   1: input, 2: default
# STDOUT:      input or default
{
    if [[ -z $1 ]] ; then
        echo "$2"
    else
        echo "$1"
    fi
    return 0
}

useExistingConfig="n"
cd "${HOME}" || printError "Failed to change to home directory"
if [[ -f ".ssmtprc" ]] ; then
    echo "ssmtp is already configured"
    cat .ssmtprc
    read -r -p "Do you want to use the existing configuration? [y/n] " useExistingConfig
    if ! [[ ${useExistingConfig} =~ ^[ny]{1}$ ]] ; then
        printError "Invalid input."
    fi
fi

if [[ ${useExistingConfig} == "n" ]] ; then
    read -r -p "Insert the email server (Default: smtp.gmail.com:587): " emailServer
    read -r -p "Insert the emailadress: " emailAdress
    read -r -p "Insert the password: " password
    read -r -p "Use STARTTLS? (Default:y) [y/n] " useStartTLS
    emailServer=$(ifEmptyReplaceWithDefault "${emailServer}" "smtp.gmail.com:587")
    useStartTLS=$(ifEmptyReplaceWithDefault "${useStartTLS}" "y")
    if [[ ${useStartTLS} == "y" ]] ; then
        useStartTLS="YES"
    else
        useStartTLS="NO"
    fi
    
    config="$(cat << EOF
mailhub=${emailServer}
AuthUser=${emailAdress}
AuthPass=${password}
AuthMethod=LOGIN
UseSTARTTLS=${useStartTLS}
TLS_CA_File=/etc/pki/tls/certs/ca-bundle.crt
EOF
)"
    printVerbose "Creating new configuration file (~.ssmtprc)"
    echo "${config}" > .ssmtprc
    # Only user should be able to read the password in the config file
    chmod 600 .ssmtprc
    printVerbose "${config}"

elif [[ ${useExistingConfig} == 'y' ]] ; then
    emailAdress=$(grep "AuthUser" .ssmtprc | cut -d = --field 2)
fi


today="$(date +'%d-%m-%Y')"
emailString="Subject: Calendar ${today}

$(for i in "${result[@]}"; do echo "$i"; done)"

[[ verboseMode -eq 1 ]] && ssmtp -vvv -C "${HOME}/.ssmtprc" "${emailAdress}" <<< "${emailString}"
[[ verboseMode -eq 0 ]] && ssmtp -C "${HOME}/.ssmtprc" "${emailAdress}" <<< "${emailString}"


exit 0
