#!/bin/sh
# 
# GeoIP blocking with OpenBSD pf
#
# Setup
# 1. useradd -s /sbin/nologin $PFBLOCK_USER
# 2. Configure doas for PFBLOCK_USER to use pfctl 
# 3. Setup crontab, something like:
#    @weekly    /bin/sh /usr/local/bin/geoipblock.sh
# 4. install -m 600 -o $PFBLOCK_USER -g $PFBLOCK_USER /dev/null "$BLACKLIST"
# 5. Configure pf.conf:
#    table <geoipblock> persist file "/etc/pf.geoipblock"
#    block in quick on egress from <geoipblock> 
#
set -e

COUNTRY_CODES="cn az by kz kg ru tj tm uz vn id"
PATTERN="^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?"
PF_TABLE="geoipban"
PFBLOCK_USER="_pfblock"
BLACKLIST="/etc/pf.geoipban"
_tmpbuf=$(mktemp)

trap 'rm $_tmpbuf' EXIT

if [ ! -O "$BLACKLIST" ]; then
    logger "$BLACKLIST: Permission denied"
    exit 1
fi

for country_code in $COUNTRY_CODES; do 
    ftp -o - "https://ipdeny.com/ipblocks/data/countries/$country_code.zone" | \
        grep -oE "$PATTERN" >> $_tmpbuf
    sleep 1
done

> "$BLACKLIST"
sort -u $_tmpbuf > "$BLACKLIST"
rm $_tmpbuf

doas -u $PFBLOCK_USER pfctl -t "$PF_TABLE" -T replace -f "$BLACKLIST"

logger "$BLACKLIST: updated"
