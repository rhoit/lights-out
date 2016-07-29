#!/bin/bash

__PKG_NAME__="lights-out-puzzle"

function Usage {
    echo -e "Usage: $__PKG_NAME__ [OPTIONS] [LEVEL]";
    echo -e "\t-b | --board\tboard size"
    echo -e "\t-d | --debug [FILE]\tdebug info to file provided"
    echo -e "\t-h | --help\tDisplay this message"
}

GETOPT=$(getopt -o b:d:h\
              -l board:,debug,help\
              -n "$__PKG_NAME__"\
              -- "$@")

if [ $? != "0" ]; then exit 1; fi

eval set -- "$GETOPT"

BOARD_SIZE=5
LEVEL=1
export WD="$(dirname $(readlink $0 || echo $0))"
exec 3>/dev/null

while true; do
    case $1 in
        -d|--debug)   exec 3>$2; shift 2;;
        -h|--help)    Usage; exit;;
        -v|--version) cat $WD/.version; exit;;
        --)           shift; break
    esac
done

exec 2>&3 # redirecting errors

# extra argument
for arg do
    LEVEL=$arg
    break
done

#----------------------------------------------------------------------
# game LOGIC

header="\033[1m$__PKG_NAME__\033[m (https://github.com/rhoit/lights-out)"
colors[0]="\e[8m"
colors[1]="\e[8;47m"

export WD_BOARD=$WD/ASCII-board
source $WD_BOARD/board.sh


function key_react {
    read -d '' -sn 1
    test "$REPLY" == $'\e' && {
        read -d '' -sn 1 -t1
        test "$REPLY" == "[" && {
            read -d '' -sn 1 -t1
            case $REPLY in
                M) mouse_read_pos;;
            esac
        }
    }
}


function mouse_read_pos {
    IFS= read -r -d '' -sn1 -t1 _MOUSE1 || break 2
    IFS= read -r -d '' -sn1 -t1 _MOUSE2 || break 2
    IFS= read -r -d '' -sn1 -t1 _MOUSE3 || break 2
    # echo -n "$_MOUSE1" | od -An -tuC >&3
    let mouse_x="$(echo -n "$_MOUSE2" | od -An -tuC) - 32"
    let mouse_y="$(echo -n "$_MOUSE3" | od -An -tuC) - 32"
    >&3 echo "mouse: ($_MOUSE1 $mouse_x $mouse_y)"
}


function check_endgame { # $1: end game
    let "$1" && {
        tput cup $offset_figlet_y 0; board_banner -c -w $COLUMNS $status
        exit
    }

    for ((i=N-1; i > 0; i--)); do
        [[ "${board[$i]}" == "1" ]] && return
    done

    tput cup 9 0; board_banner -c -w $COLUMNS "COMPLETED"
    tput cup $board_max_y $COLUMNS
    return 1
}


function status {
    printf "moves: %-9d" $moves
    echo
}


function play_level { # $* board
    ## get-game-specs
    declare board=($@)

    ## create board
    status
    board_print $BOARD_SIZE

    test -z $NOPLAY || {
        board_update
        echo
        echo "PRESS ENTER TO SEE NEXT LEVEL"
        read
        return
    }

    ## set-loop variables
    mouse_x=0 mouse_y=0

    ## game-loop
    while true; do
        board_update
        key_react
        (( mouse_x < offset_x + 2 )) && continue
        (( mouse_x > _max_x - 2 )) && continue
        (( mouse_y < offset_y + 2 )) && continue
        (( mouse_y > _max_y - 1 )) && continue

        let row="(mouse_y - offset_y - 1) / (_tile_height + 1)"
        let col="(mouse_x - offset_x - 1) / (_tile_width + 1)"
        let index="row * BOARD_SIZE + col"
        >&3 echo row: $row col: $col index: $index

        let board[index]=board[index]?0:1

        let t="$index - $board_size"
        let r="$index + 1"
        let b="$index + $board_size"
        let l="$index - 1"

        (( 0 <= t )) && let board[t]=board[t]?0:1
        (( row == r/board_size )) && let board[r]=board[r]?0:1
        (( N > b )) && let board[b]=board[b]?0:1
        (( 0 < l && row == l/board_size )) && let board[l]=board[l]?0:1

        let moves++
        board_tput_status; status
        check_endgame || return
    done
}

declare score=0
trap "check_endgame 1; exit" INT #handle INTTRUPT
let N="BOARD_SIZE * BOARD_SIZE"
board_init $BOARD_SIZE
echo -n $'\e'"[?9h" # enable-mouse

LMAX=$(cat $WD/levels | wc -l)
for ((level=LEVEL; level<=$LMAX; level++)); do
    clear
    specs=$(sed -n "${level}p" $WD/levels)
    test -z "$specs" && exit
    unset board_old
    declare moves=0
    >&3 echo level:$level "($specs)"
    echo -e $header
    play_level ${specs[@]}
done
