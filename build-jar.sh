#!/bin/sh
# Rebuilds lib/openapi2dita.jar. Needs a JDK (11+) and a DITA-OT 4.x install
# for the compile classpath:   DITA_HOME=/path/to/dita-ot ./build-jar.sh
set -e
cd "$(dirname "$0")"
: "${DITA_HOME:?Set DITA_HOME to your DITA-OT directory}"
rm -rf build && mkdir -p build/classes lib
javac --release 11 -encoding UTF-8 -d build/classes \
  -cp "$DITA_HOME/lib/*" \
  src/openapi2dita/*.java
jar --create --file lib/openapi2dita.jar -C build/classes .
rm -rf build
echo "Built lib/openapi2dita.jar"
