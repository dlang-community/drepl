#!/bin/sh

set -e -v

BUILD=${BUILD:=release}
dub build -b ${BUILD} -c sandbox
dub build -b ${BUILD} -c server

rsync -ravzL --delete --no-whole-file drepl_server drepl_sandbox examples/favicon.ico root@kvm2.dawg.eu:/home/dawg/drepl/
rsync -avzL --delete --no-whole-file drepl.service root@kvm2.dawg.eu:/usr/lib/systemd/system/
ssh root@kvm2.dawg.eu 'setcap cap_net_bind_service=ep /home/dawg/drepl/drepl_server'
ssh root@kvm2.dawg.eu 'systemctl daemon-reload && systemctl restart drepl.service && sleep 1 && systemctl status drepl.service'
