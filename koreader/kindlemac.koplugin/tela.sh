#!/bin/sh
# Streams the screen to `kindle servir` on the Mac until /tmp/kindlemac-tela.stop exists.
# usage: tela.sh HOST PORT TOKEN [DELAY_US]
HOST=$1
PORT=$2
TOKEN=$3
DELAY=${4:-333000}
STOP=/tmp/kindlemac-tela.stop
PIDF=/tmp/kindlemac-tela.pid
NCPID=/tmp/kindlemac-tela.nc
FIFO=/tmp/kindlemac-tela.fifo

rm -f "$STOP"
echo $$ > "$PIDF"

F=/sys/class/graphics/fb0
S=$(cat $F/stride)
X=$(cut -d, -f1 $F/virtual_size)
H=$(sed -n 's/.*:[0-9]*x\([0-9]*\).*/\1/p' $F/modes)
[ -n "$H" ] || H=$(( $(cut -d, -f2 $F/virtual_size) / 2 ))
B=$(cat $F/bits_per_pixel)

produce() {
    echo "KINDLE-FB $TOKEN $X $H $S $B"
    while [ ! -f "$STOP" ]; do
        # the half of the double buffer that is on screen
        off=$(cut -d, -f2 $F/pan)
        dd if=/dev/fb0 bs="$S" skip="$off" count="$H" 2>/dev/null | gzip -1 || exit 0
        usleep "$DELAY"
    done
}

while [ ! -f "$STOP" ]; do
    rm -f "$FIFO"
    mkfifo "$FIFO"
    produce > "$FIFO" &
    P=$!
    nc "$HOST" "$PORT" < "$FIFO" > /dev/null &
    N=$!
    echo $N > "$NCPID"
    wait $N
    kill $P 2>/dev/null
    wait $P 2>/dev/null
    [ -f "$STOP" ] || sleep 3
done
rm -f "$FIFO" "$PIDF" "$NCPID" "$STOP"
