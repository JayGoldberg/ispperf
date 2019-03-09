#!/bin/bash

# The MIT License, Copyright (c) 2010, MaDeuce
#
# =========================================================================
# This command measures latency and bandwidth of an internet connection from the command line.
# It uses hosts that participate in speedtest.net.  Output is in the form of a csv file.
# As designed, speedtest.net can be used to test latency and bandwidth only from a browser
# and only then, manually.  I wanted to be able to test latency and bandwidth repeatedly
# via cron, or similar, and to record historical data, so I created this script.  Output
# is to stdout. If I'd have known at the beginning that I'd write this much code, I'd
# have done it in python.

# These are some participating hosts.  If you want to use a host from another location, you will
# have to run the test from your browser and capture headers to determine the correct URL. Or, if
# you are a flash hacker, you can get all of them from the swf file used to implement the test.
# Note that URLs can differ between hosts, so you do need to determine the correct one to use
# on a case by case basis.
#
# urls from here: https://www.speedtestserver.com/
AUSTIN_TX="aus.ookla.gfsvc.com:3002"
SANJOSE_CA="ookla-a.equinix-sj.sonic.net:8080"
PALOALTO_CA="sfo.ookla.gfsvc.com:3002"
MIAMI_FL="mia.speedtest.sbcglobal.net:8080"
BOSTON_MA="speedtest-server.starry.com:8080"
CHICAGO_IL="speedtest-ookla-prod-001-chi.ff.avast.com:8080"
RESTON_VA="speed1.iad2.inforelay.net:8080"
PORTLAND_OR="speedtestportland.myfairpoint.net:8080"
# opusnet uses aspx for upload, as opposed to php. i don't want to implement aspx support, so don't use it
# i'm sure there are other windows hosts. if you add hosts to this and see HTML output from upload(),
# it means that the host is windows.  you should skip that host or implement aspx in addition to php.
HOSTS="$AUSTIN_TX $PALOALTO_CA $MIAMI_FL $BOSTON_MA $CHICAGO_IL $PORTLAND_OR $RESTON_VA $SANJOSE_CA"

# output a timestamp
write_timestamp () {
    date "+%m%d,%H:%M:%S," | tr -d "\n"
}

r13 () {
    # 13 digit random number
    echo "${RANDOM}${RANDOM}${RANDOM}" | cut -c -13 -
}

title () {
cat<<EOF
#p = ping record
#p,***d,HH:MM:SS,min,avg,max,stddev
#l = latency record
#l,***d,HH:MM:SS,host,totalT,namelookupT,connectT,starttransferT,size,speed
#d = download bandwidth record
#d,***d,HH:MM:SS,host,totalT,namelookupT,connectT,starttransferT,size,speed
#u = download bandwidth record
#u,***d,HH:MM:SS,host,totalT,namelookupT,connectT,starttransferT,size,speed
EOF
}

# Redundancy in the next 4 functions should be factored out someday.  However,
# I'll redo the script in python before I do that, I think.

# test download speed
download () {
    HOST=$1
    SIZE=$2
    MAXSECS=$3
    FMT="%{time_total},%{time_namelookup},%{time_connect},%{time_starttransfer},%{size_download},%{speed_download}\n"
    RND=$(r13)
    URL="$HOST/random${SIZE}x${SIZE}.jpg?x=${RND}-1"
    HOST=$(echo $HOST | sed -e s/\\\/.*$//g -e s/:.*$//g)
    echo -n 'd,'
    write_timestamp
    echo -n "${HOST},"
    curl -m ${MAXSECS} -s -w "$FMT" $URL -o /dev/null
}

# test upload speed
upload () {
    HOST=$1
    SIZE=$2
    MAXSECS=$3
    # generate random segment of data of $SIZE bytes
    DATA="$(hexdump -C /dev/urandom | cut -b9- | cut -d"|" -f1 | tr -d ' \t\n\r'|head -c ${SIZE})"
    FMT="%{time_total},%{time_namelookup},%{time_connect},%{time_starttransfer},%{size_upload},%{speed_upload}\n"
    RND="$(r13)"
    URL="$HOST/upload.php?x=0.${RND}"
    HOST=$(echo $HOST | sed -e s/\\\/.*$//g -e s/:.*$//g)
    echo -n 'u,'
    write_timestamp
    echo -n "${HOST},"
    curl -m ${MAXSECS} -s -w "$FMT" -d $DATA -o /dev/null $URL
}

# test http latency by getting small file
latency () {
    HOST=$1
    MAXSECS=$2
    RND=$(r13)
    URL="$HOST/latency.txt?x=${RND}"
    HOST=$(echo $HOST | sed -e s/\\\/.*$//g -e s/:.*$//g)
    echo -n 'l,'
    write_timestamp
    echo -n "${HOST},"
    FMT="%{time_total},%{time_namelookup},%{time_connect},%{time_starttransfer},%{size_download},%{speed_download}\n"
    curl -m ${MAXSECS} -s -w "$FMT" $URL -o /dev/null
}

# test IP latency via ping
pingit () {
    HOST=$1
    MAXSECS=$2
    # just want hostname -- get rid of any http url fragment or port number
    HOST=$(echo $HOST | sed -e s/\\\/.*$//g -e s/:.*$//g)
    echo -n "p,"
    write_timestamp
    echo -n "${HOST},"
    # ping the host. hang on to the results so return code can be kept
    PING_VALUE="$(timeout $MAXSECS ping -c3 -q $HOST)"
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        # ping was successful
        # output min/avg/max/stdev
        echo $PING_VALUE | fgrep round-trip | sed s/^.*=//g | sed -e 's/\//,/g' -e 's/ //g' -e 's/ms//g'
    else
        # some speedtest.net hosts do not respond to pings
        # ping was unsuccessful
        echo "0,0,0,0"
    fi
}

if ! type timeout 2>&1 >/dev/null; then
  timeout () {
    local timeout_secs=${1:-10}
    shift

    [ ! -z "${timeout_secs//[0-9]}" ] && { return 65; }
    
    # subshell
    ( 
      "$@" &
      child=$!
      #trap - '' SIGTERM #why would we need this?
      (       
        sleep $timeout_secs
        kill $child 2> /dev/null # TODO returns 143 instead of "real" timeout's 124
      ) &
      wait $child
    )
  }
  export timeout
fi

# They use jpeg images with random content as a paylod for testing downloads.  The images are all
# square (i.e., 'n x n').  There are nine fixed sizes of images.
DOWNLOAD_SIZES="350 500 1000 1500 2000 2500 3000 3500 4000"

# For some reason, they only use two sizes of payloads for upload testing.  25097 and 151325 bytes.
# The payloads are simply random strings which are generated on the client side.  I don't think that their
# exact size is important, nor do I think anything would prevent you from adding your own sizes.
UPLOAD_SIZES="25097 151325"

title

while true; do
    for HOST in $HOSTS; do
        TMOUT=30                             # giveup after 30 seconds
        latency $HOST $TMOUT
        pingit $HOST $TMOUT
        for SIZE in $DOWNLOAD_SIZES; do
            TMOUT=$((60*10))                 # giveup after 10 minutes
            download $HOST $SIZE $TMOUT
        done
        for SIZE in $UPLOAD_SIZES; do
            TMOUT=$((60*10))                 # giveup after 10 minutes
            upload $HOST $SIZE $TMOUT
        done
    done
done
