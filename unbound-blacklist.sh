#!/bin/sh
#
# Script used with cron on OpenBSD to feed unbound a blacklist of domains not
# to forward. Assists in weeding out adservers and various unwanted traffic.
#
# Setup:
# sh unbound-blacklist.sh init
#
# Installs the script in /usr/local/bin, adds script user, adds necessary 
# privilege escalation rules to doas.conf, installs crontab and creates keys 
# for unbound-control.
# 
# Manual:
# doas -u _blacklist sh /usr/local/bin/unbound-blacklist.sh
#
USER="_blacklist"
UNBOUND_USER="_unbound"
UNBOUND_CHROOT="/var/unbound"
PATTERN="^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$"
BLACKLIST_CONF="$UNBOUND_CHROOT/etc/blacklist.conf"
SCRIPT_NAME="$(basename $0)"

# Custom list
# Add custom domains here
CUSTOM_BLACKLIST=$(cat << EOF
my.callhome.iot.trash.com
EOF
)

# Feed list
# Expects file to contain one domain per line, else $PATTERN wont match.
# Add '#' to beginning of line to disalba a feed.
URLS=$(cat << EOF
https://pgl.yoyo.org/adservers/serverlist.php?hostformat=plain&showintro=0&mimetype=plaintext
https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
https://block.energized.pro/ultimate/formats/domains.txt
https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
https://mirror1.malwaredomains.com/files/justdomains
#https://v.firebog.net/hosts/AdguardDNS.txt
#https://v.firebog.net/hosts/Airelle-hrsk.txt
#https://v.firebog.net/hosts/Airelle-trc.txt
#https://v.firebog.net/hosts/BillStearns.txt
#https://v.firebog.net/hosts/Easylist.txt
#https://v.firebog.net/hosts/Easyprivacy.txt
#https://v.firebog.net/hosts/Kowabit.txt
#https://v.firebog.net/hosts/Prigent-Ads.txt
#https://v.firebog.net/hosts/Prigent-Malware.txt
#https://v.firebog.net/hosts/Prigent-Phishing.txt
#https://v.firebog.net/hosts/Shalla-mal.txt
#https://v.firebog.net/hosts/static/w3kbl.txt
EOF
)

_tmpunsorted="$(mktemp)" || exit 1
_tmpsorted="$(mktemp)" || exit 1

# Bailout with an error message and restore conf
error() {
    logger "$SCRIPT_NAME: ${1:-"failed"}"
    exit 1
}

# Remove temporary buffers
cleanup() {
    rm -f $_tmpunsorted $_tmpsorted
}

trap cleanup EXIT

# Initialize/install
init() {
    if [ $(id -u) -ne 0 ]; then
        echo "You're not root"
        exit 1
    fi

    # Copy script
    echo "== Installing $SCRIPT_NAME to /usr/local/bin"
    install -m 644 -o root -g bin $0 /usr/local/bin/

    # Add user
    if ! id -u $USER 2>/dev/null; then
        echo "== Creating user $USER"
        useradd -s /sbin/nologin $USER
    fi

    # Create blacklist
    echo "== Creating empty $BLACKLIST_CONF"
    install -m 640 -o $USER -g $UNBOUND_USER /dev/null "$BLACKLIST_CONF"

    # Configure doas (sloppy, might be a better way than using grep)
    echo "== Setting up doas"
    local _doascnf_checkconf="permit nopass $USER as $UNBOUND_USER cmd unbound-checkconf"
    local _doascnf_reload="permit nopass $USER as $UNBOUND_USER cmd unbound-control args reload"

    grep "$_doascnf_checkconf" /etc/doas.conf 2>/dev/null || \
        echo "$_doascnf_checkconf" >> /etc/doas.conf
    grep "$_doascnf_reload" /etc/doas.conf 2>/dev/null || \
        echo "$_doascnf_reload" >> /etc/doas.conf

    # Install crontab
    echo "== Installing crontab"
    local _crontmp=$(mktemp)
    printf "PATH=/bin:/sbin:/usr/bin:/usr/sbin\n@daily\t/bin/sh /usr/local/bin/$SCRIPT_NAME\n" > $_crontmp
    crontab -u $USER $_crontmp
    rm -f $_crontmp

    # Configure unbound
    echo "== Generating keys for unbound-control-setup"
    unbound-control-setup
    cd $UNBOUND_CHROOT/etc
    chown root:$UNBOUND_USER unbound_control.* unbound_server.* 
    rcctl restart unbound # doesn't make any sense if unbound-control isn't enabled

    exit 0
}

main() {
    [ "$1" == "init" ] && init

    # Retrieve URLs and remove duplicates
    echo "$URLS" | grep -vE '^#' | xargs ftp -o -  > $_tmpunsorted || \
        error "Fetching URLs failed."
    sort -fu $_tmpunsorted > $_tmpsorted

    # Create new empty blacklist
    printf "# Managed by $SCRIPT_NAME\n# Last updated: $(date)\n" > $BLACKLIST_CONF
    
    # Validate domain names and create unbound conf
    while read name; do
        if echo "$name" | grep -oE "$PATTERN" 1>/dev/null; then
            # Respond with NXDOMAIN for all blacklisted domains
            echo "local-zone: \"$name\" always_nxdomain" >> $BLACKLIST_CONF
        fi
    done < $_tmpsorted

    # Add custom domains
    # TODO: this is a hack. Fix this and include in domain validation before
    # adding
    for name in $CUSTOM_BLACKLIST; do
        echo "local-zone: \"$name\" always_nxdomain" >> $BLACKLIST_CONF
    done


    # Check configuration syntax. Empty blacklist and bail out on error
    if ! doas -u $UNBOUND_USER unbound-checkconf 1>/dev/null; then
        echo > $BLACKLIST_CONF
        error "Syntax error in unbound configuration."
    fi

    # Reload server and conf
    # XXX: also flushes cache, we may want to dump and restore this
    if ! doas -u $UNBOUND_USER unbound-control reload 1>/dev/null; then
        error "Reload unbound failed."
    fi

    # Log
    logger "$SCRIPT_NAME: Updated $BLACKLIST_CONF with $(wc -l $_tmpsorted | \
        awk '{print $1}') entries"
}

main "$@"
