#!/bin/bash
#
# <bitbar.title>TrackingTime</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>Anthony Jackson</bitbar.author>
# <bitbar.author.github>expelledboy</bitbar.author.github>
# <bitbar.desc>Integration to trackingtime.co</bitbar.desc>

export PATH=/usr/local/bin:$PATH

# -- config

USERNAME='<USERNAME>'
PASSWORD='<PASSWORD>'
WORK_TIME=25

# -- vars

DATA_FILE=$TMPDIR/bitbar-trackingtime
CURRENT_TIME=$(date +%s)

# -- private functions

call() {
  METHOD=$1
  URL=$2

  shift 2

  curl -s \
    -X $METHOD \
    -u $USERNAME:$PASSWORD \
    -H "Content-Type: application/json" \
    -H "User-Agent: 'TrackingTime with Bitbar v1.0 (anthony@betaplum)'" \
    $@ \
    "https://app.trackingtime.co/api/v4$URL"
}

load_data() {
  source $DATA_FILE;
  MODE=${MODE:-init}
  if [ ! -z "$TASK_ID" ]; then
    JQ_CURRENT_TAKE=".data[] | select(.id == $TASK_ID) | .name"
    NAME=$(echo $TASKS | jq -r "$JQ_CURRENT_TAKE")
  fi
}

save_data() {
  cat << EOF > $DATA_FILE
TASKS='$TASKS'
MODE='$MODE'
TASK_ID='$TASK_ID'
START_TIME='$START_TIME'
BREAK_TIME='$BREAK_TIME'
UPDATED='$UPDATED'
EOF
}

notify() {
  TITLE=$1
  BODY=$2
  SOUND=$3

  NOTIFY=" display notification \"$BODY\""
  NOTIFY+=" with title \"$TITLE\""

  if [ ! -z "$SOUND" ]; then
    NOTIFY+=" sound name \"$SOUND\""
  fi

  osascript -e "$NOTIFY" &> /dev/null
}

load_tasks() {
  TASKS=$(call GET /tasks)
  UPDATED=$CURRENT_TIME
}

print_time() {
  T_DIFF=$((CURRENT_TIME - START_TIME))

  ((h=${T_DIFF}/3600))
  ((m=(${T_DIFF}%3600)/60))
  ((s=${T_DIFF}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}

# commands

start_task() {
  MODE=tracking
  START_TIME=$CURRENT_TIME
  BREAK_TIME=$((CURRENT_TIME+60*$WORK_TIME))
  NOW=$(date -jf "%s" $CURRENT_TIME +"%Y-%m-%d %H:%M:%S")
  TIMEZONE=$(date -jf "%s" $CURRENT_TIME +"%Z%z" | tr -d 0)
  call POST "/tasks/track/$TASK_ID" \
    --data "'{\"date\":\"$NOW\",\"timezone\":\"$TIMEZONE\",\"stop_running_task\":true}'"
  save_data
  notify "Tracking Time" "$NAME" "Glass"
}

stop_task() {
  MODE=idle
  NOW=$(date -jf "%s" $CURRENT_TIME +"%Y-%m-%d %H:%M:%S")
  TIMEZONE=$(date -jf "%s" $CURRENT_TIME +"%Z%z" | tr -d 0)
  call POST "/tasks/stop/$TASK_ID" \
    --data "'{\"date\":\"$NOW\",\"timezone\":\"$TIMEZONE\",\"stop_running_task\":true}'"
  save_data
  notify "Stopped Tracking" "$NAME" "Blow"
}

main() {
  case $MODE in
    "init")
      load_tasks
      MODE=idle
      save_data
      echo "..." ;;
    "idle")
      echo "⌚" ;;
    "tracking")
      if [[ $CURRENT_TIME -gt $BREAK_TIME ]]; then
        BREAK_TIME=$((CURRENT_TIME+60*1))
        save_data
        notify "Pomodoro" "Time for a break!" "Submarine"
      fi
      echo "⌚ $NAME $(print_time) | bash=\"$0\" param1=stop terminal=true" ;;
  esac

  LAST_UPDATED=$((CURRENT_TIME - UPDATED))

  if [[ $LAST_UPDATED -gt 30 ]]; then
    load_tasks
    JQ_TRACKING_TASK='.data[] | select(.tracking == true) | "\(.name)|\(.id)|\(.users[0].event.start)"'
    IFS='|' read -r NAME TASK_ID START_TIME < <(echo $TASKS | jq -rc "$JQ_TRACKING_TASK")
    if [ -z "$TASK_ID" ]; then
      MODE=idle
    else
      MODE=tracking
      START_TIME=$(date -jf "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s)
    fi
    save_data
  fi

  echo "---";

  JQ_ACTIVE_TASKS='.data[] | select(.type == "PERSONAL") | "\(.name)|\(.id)"'

  while IFS='|' read -r NAME ID; do

    case $MODE in
      "idle")
        echo "$NAME | bash=\"$0\" param1=start param2=$ID terminal=true" ;;
      "tracking")
        echo "$NAME" ;;
    esac

  done < <(echo $TASKS | jq -rc "$JQ_ACTIVE_TASKS")
}

# -- engine

load_data

case "$1" in
  "start") CMD="start_task"; TASK_ID=$2; shift 2 ;;
  "stop") CMD="stop_task"; shift 1 ;;
  *) CMD="main" ;;
esac

$CMD
