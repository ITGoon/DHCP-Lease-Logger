#!/bin/bash

# Time Keeper Start
datestart=$(date +%S)

# Log all of the output of this script
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
#exec 1>>/var/log/logleasesdb.log 2>&1
exec 1>>/var/log/logleasesdb.log 2> /dev/null

# Uncomment the line above with 2>&1 on the end and comment the line
# with /dev/null on the end to get a tiny bit more verbosity


# Make a call to the Glass API
data=$(curl -s http://<IP Of Your DHCP Server>:3000/api/get_active_leases)

# Seperate each device entry with a +
plusdata=$(sed -r 's/},"1/+1/g' <<<"$data")

# Remove spaces and replace with _
# This mainly affects the MAC vendor column, it wasn't working without it
arraysp=$(sed -r 's/ /_/g' <<<"$plusdata")

# Split each device entry into their own array position
IFS='+' read -ra array <<< "$arraysp"


## FILTERING BELOW ##

# Find and get each MAC address
mcount=0
for eachmac in "${array[@]}"
do
  mac_array[mcount]=$(grep -oP '[0-9a-f]{1,2}([\.:-])(?:[0-9a-f]{1,2}\1){4}[0-9a-f]{1,2}' <<< $eachmac)
  mcount=$((mcount+1))
done

# Find and get each hostname
hcount=0
for eachhost in "${array[@]}"
do
  host_array[hcount]=$(grep -oP '(?<="host":")(.*)(?=")' <<< $eachhost)
  hcount=$((hcount + 1))
done

# Find and get each MAC Vendor
vcount=0
for eachvendor in "${array[@]}"
do
  vendor_array[vcount]=$(grep -oP '(?<="mac_oui_vendor":")(.*?)(?=")' <<< "$eachvendor")
  vcount=$((vcount+1))
done

# Find and get each lease start time
tcount=0
for eachtime in "${array[@]}"
do
  time_array[tcount]=$(grep -oP '(?<="start":)\d{10}' <<< $eachtime)
  tcount=$((tcount+1))
done
# Convert the above epoch values into time stamps
tvcount=0
for eachepoch in "${time_array[@]}"
do
  truetime[tvcount]=$(date -d @"$eachepoch")
  tvcount=$((tvcount+1))
done


# Find and get each IP
ipcount=0
for eachip in "${array[@]}"
do
  ip_array[ipcount]=$(grep -oP '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b' <<< $eachip)
  ipcount=$((ipcount+1))
done

## END FILTERING ##


# Combine each value of the above arrays into one array
finalcount=0
for eachresult in "${mac_array[@]}"
do
  finalarray[finalcount]=$(echo '"'$eachresult'"'',' '"'${truetime[finalcount]}'"'',' '"'${host_array[finalcount]}'"'',' '"'${vendor_array[finalcount]}'"'',' '"'${ip_array[finalcount]}'"')
  finalcount=$((finalcount+1))
done

# Insert each row of values from the above array into the table of devices
for i in "${finalarray[@]}"; do echo "INSERT INTO devices (mac, datetime, hostname, manufacturer, ip) values ($i);" | mysql -u YOUR-SQL-USER -pSQL-USER-PASSWORD devicedb; done

# Re-count the ID column
echo "SET @count = 0; UPDATE devices SET devices.id = @count:= @count + 1; ALTER TABLE devices AUTO_INCREMENT = 1;" | mysql -u OUR-SQL-USER -pSQL-USER-PASSWORD devicedb;

# Replace empty values in hostname and manufacturer with UNKNOWN and NoneFound
echo "UPDATE devices SET hostname='UNKNOWN' WHERE hostname='';" | mysql -u OUR-SQL-USER -pSQL-USER-PASSWORD devicedb;
echo "UPDATE devices SET manufacturer='NoneFound' WHERE manufacturer='';" | mysql -u OUR-SQL-USER -pSQL-USER-PASSWORD devicedb;


# Time Keeper End
dateend=$(date +%S)

# Set time for the log
logtime=$(date)

# Time Keeper MATH to show the run time of the script
# Also showing the total leases found
echo $logtime" This script took" "$(($dateend-$datestart))" "Seconds to run and found" $tvcount "total leases."
