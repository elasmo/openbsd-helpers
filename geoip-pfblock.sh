#!/bin/sh
# 
# GeoIP blocking with OpenBSD pf
#
# Setup
# 1. useradd -s /sbin/nologin $PFBLOCK_USER
# 2. Configure doas for PFBLOCK_USER to use pfctl 
# 3. Setup crontab to run script at regular basis
# 4. Ensure that BLACKLIST is writable by PFBLOCK_USER
# 5. Configure pf.conf:
#    table <geoipblock> persist file "/etc/pf.geoipblock"
#    block in quick on egress from <geoipblock> 
#
COUNTRY_CODES="cn az by kz kg ru tj tm uz vn id"
PF_TABLE="geoipban"
PFBLOCK_USER="_pfblock"
BLACKLIST="/etc/pf.geoipban"
_tmpbuf=$(mktemp) || exit 1

for country_code in $COUNTRY_CODES; do 
    ftp -o - "http://ipdeny.com/ipblocks/data/countries/$country_code.zone" | \
        grep -E -o '^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?' >> $_tmpbuf
    sleep 1
done

echo > "$BLACKLIST"
chmod 600 "$BLACKLIST"

sort -u $_tmpbuf > "$BLACKLIST"
rm $_tmpbuf

doas -u $PFBLOCK_USER pfctl -t "$PF_TABLE" -T replace -f "$BLACKLIST" || exit 1

logger "$BLACKLIST BLACKLIST updated."
