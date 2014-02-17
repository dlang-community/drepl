#!/bin/sh

set -e

TEMPDIR=`mktemp -d`

for proj in dmd druntime phobos; do
    curl -sSL https://github.com/D-Programming-Language/${proj}/archive/master.tar.gz | \
        tar -C ${TEMPDIR} --transform="s|^${proj}-master|${proj}|" -zxf -
done

make -C ${TEMPDIR}/dmd/src -f posix.mak -j4
make -C ${TEMPDIR}/druntime -f posix.mak -j4
make -C ${TEMPDIR}/phobos -f posix.mak -j4

cat > ${TEMPDIR}/dmd/src/dmd.conf <<EOF
[Environment]
DFLAGS=-I%@P%/../../phobos -I%@P%/../../druntime/src -L-L%@P%/../../phobos/generated/linux/release/64 -L-L%@P%/../../druntime/lib -L--export-dynamic
EOF

export LD_LIBRARY_PATH=${TEMPDIR}/phobos/generated/linux/release/64

curl -L http://code.dlang.org/files/dub-0.9.21-rc.4-linux-x86_64.tar.gz > ${TEMPDIR}/dub.tar.gz
tar -C ${TEMPDIR} -zxf ${TEMPDIR}/dub.tar.gz

${TEMPDIR}/dub test --compiler=${TEMPDIR}/dmd/src/dmd

rm -rf ${TEMPDIR}
