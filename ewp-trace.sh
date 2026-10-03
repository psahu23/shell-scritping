#!/bin/sh
# =============================================================================
# Prepared by : Pabitra Kumar Sahu
# =============================================================================
# EWP Live Trace - POSIX launcher.
TMP="${TMPDIR:-/tmp}/ewp_live_trace_$$.bash"
trap 'rm -f "$TMP"' 0 1 2 3 15

awk '
/^# BEGIN_EWP_BASH$/ {inside=1; next}
/^# END_EWP_BASH$/   {inside=0; exit}
inside {
    sub(/^# ?/, "", $0)
    print
}
' "$0" > "$TMP" || exit 1

command -v bash >/dev/null 2>&1 || {
    echo "ERROR: bash is required but was not found."
    exit 1
}

exec bash "$TMP" "$@"

# BEGIN_EWP_BASH
## ###############################################################################
## EWP LIVE TRACE & LOG CORRELATION TOOL
## Prepared by: Pabitra Kumar Sahu
#
## Supports:
##   - Kubernetes m3/co/am pods
##   - AM Remote VM
##   - Multiple targets
##   - Passwordless SSH setup
##   - Generic comma-separated search terms
##   - EWP inbound API + request/response correlation
##   - 3PP outbound request/response capture
##   - Error/business-status detection
##   - CSV/XLSX output
##   - Credential masking in reports
## ###############################################################################
#
# set -u
# set -o pipefail
#
# OUTPUT_ROOT="${HOME}/ewp_trace_output"
# TRACE_PACKAGE="com.ericsson"
# TRACE_LEVEL="TRACE"
# SSH_KEY="${HOME}/.ssh/ewp_am_trace_ed25519"
#
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# NC='\033[0m'
#
# die() { echo -e "${RED}ERROR:${NC} $1"; exit 1; }
# need_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed."; }
# safe_name() { echo "$1" | sed 's/[^A-Za-z0-9._-]/_/g'; }
#
# cleanup_captures() {
#     for pid in ${CAPTURE_PIDS:-}; do
#         kill "$pid" 2>/dev/null || true
#     done
#     sleep 1
#     for pid in ${CAPTURE_PIDS:-}; do
#         kill -9 "$pid" 2>/dev/null || true
#     done
# }
#
# disable_traces() {
#     echo
#     echo "Disabling TRACE for selected targets..."
#
#     if [ "${SOURCE_CHOICE:-}" = "1" ] && command -v lwac-cli >/dev/null 2>&1; then
#         for component in "${TRACE_COMPONENTS[@]:-}"; do
#             [ -n "$component" ] || continue
#             echo "  K8S: disabling TRACE for $component"
#             lwac-cli -n "$component" log "$TRACE_PACKAGE" --level INFO >/dev/null 2>&1 || \
#                 echo "  WARNING: unable to disable TRACE for $component"
#         done
#     fi
#
#     if [ "${SOURCE_CHOICE:-}" = "2" ] && [ -n "${AM_HOST:-}" ] && [ -n "${AM_USER:-}" ]; then
#         for instance in "${TRACE_AM_INSTANCES[@]:-}"; do
#             [ -n "$instance" ] || continue
#             props="/opt/lwac/apps/${instance}/logging.properties"
#             echo "  AM VM: disabling TRACE for $instance"
#             ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" \
#                 "sudo sed -i -E 's/^[[:space:]]*com\\.ericsson\\.level=.*/com.ericsson.level=INFO/; s/^[[:space:]]*com\\.ericsson\\.lwac\\.level=.*/com.ericsson.lwac.level=INFO/' '$props'" \
#                 >/dev/null 2>&1 || echo "  WARNING: unable to disable TRACE for $instance"
#         done
#     fi
#
#     TRACE_COMPONENTS=()
#     TRACE_AM_INSTANCES=()
# }
#
# cleanup() {
#     cleanup_captures
#     disable_traces
# }
#
# trap 'cleanup; exit 130' INT TERM
#
# need_cmd date
# need_cmd grep
# need_cmd sed
# need_cmd awk
# need_cmd sort
# need_cmd kubectl
# need_cmd ssh
# need_cmd ssh-keygen
#
# mkdir -p "$OUTPUT_ROOT"
#
# echo
# echo "======================================================================"
# echo "       EWP LIVE TRACE & LOG CORRELATION - MULTI SOURCE"
# echo "       Prepared by : Pabitra Kumar Sahu"
# echo "======================================================================"
# echo
# echo "Current kubectl context:"
# kubectl config current-context 2>/dev/null || true
# echo
# echo "Current kubectl namespace/context is used automatically."
# echo
#
# read -rp "Select source [1=Kubernetes pods, 2=AM Remote VM]: " SOURCE_CHOICE
#
# RUN_ID="$(date +%Y%m%d_%H%M%S)"
# RUN_DIR="${OUTPUT_ROOT}/run_${RUN_ID}"
# mkdir -p "$RUN_DIR"
#
# declare -a TARGET_NAMES
# declare -a TARGET_TYPES
# declare -a TARGET_PIDS
# declare -a TRACE_COMPONENTS
# declare -a TRACE_AM_INSTANCES
# CAPTURE_PIDS=""
#
## ###############################################################################
## KUBERNETES
## ###############################################################################
# if [ "$SOURCE_CHOICE" = "1" ]; then
#
#     need_cmd lwac-cli
#
#     echo
#     echo "Select components (example: 1 or 1,2,5):"
#     echo "  1) m3"
#     echo "  2) co"
#     echo "  3) am"
#     echo "  4) ns"
#     echo "  5) loan"
#     read -rp "Enter choice(s): " COMP_CHOICE
#
#     declare -a CHOSEN_COMPONENTS
#     IFS=',' read -ra COMP_SELECTED <<< "$COMP_CHOICE"
#     
#     for c in "${COMP_SELECTED[@]}"; do
#         c="$(echo "$c" | xargs)"
#         case "$c" in
#             1) CHOSEN_COMPONENTS+=("m3") ;;
#             2) CHOSEN_COMPONENTS+=("co") ;;
#             3) CHOSEN_COMPONENTS+=("am") ;;
#             4) CHOSEN_COMPONENTS+=("ns") ;;
#             5) CHOSEN_COMPONENTS+=("loan") ;;
#             *) echo -e "${YELLOW}Warning: Invalid choice $c ignored.${NC}" ;;
#         esac
#     done
#
#     [ "${#CHOSEN_COMPONENTS[@]}" -gt 0 ] || die "No valid components selected."
#
#     # Build an awk pattern to find pods across all chosen components
#     AWK_PATTERN="^("
#     for comp in "${CHOSEN_COMPONENTS[@]}"; do
#         AWK_PATTERN="${AWK_PATTERN}${comp}|"
#     done
#     AWK_PATTERN="${AWK_PATTERN%|})-"
#
#     echo
#     echo "Finding Running pods for selected components..."
#     mapfile -t POD_LIST < <(
#         kubectl get pods --no-headers 2>/dev/null |
#         awk -v p="$AWK_PATTERN" '$1 ~ p && $3=="Running" {print $1}'
#     )
#
#     [ "${#POD_LIST[@]}" -gt 0 ] || die "No Running pods found for selected components."
#
#     echo
#     echo "Available Running pods:"
#     for i in "${!POD_LIST[@]}"; do
#         printf "  %d) %s\n" "$((i+1))" "${POD_LIST[$i]}"
#     done
#
#     echo
#     read -rp "Select one or multiple pods (example: 1 or 1,2,3): " POD_SELECTION
#     IFS=',' read -ra SELECTED <<< "$POD_SELECTION"
#
#     SELECTED_COUNT=0
#     for n in "${SELECTED[@]}"; do
#         n="$(echo "$n" | xargs)"
#         [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid pod selection: $n"
#         [ "$n" -ge 1 ] && [ "$n" -le "${#POD_LIST[@]}" ] || die "Invalid pod number: $n"
#
#         POD="${POD_LIST[$((n-1))]}"
#         LWAC_COMPONENT="$(echo "$POD" | sed -E 's/-[0-9]+$//')"
#
#         echo
#         echo "Selected pod: $POD"
#         echo "LWAC component: $LWAC_COMPONENT"
#         echo "Enabling TRACE..."
#
#         if ! lwac-cli -n "$LWAC_COMPONENT" log "$TRACE_PACKAGE" --level "$TRACE_LEVEL"; then
#             echo -e "${YELLOW}WARNING: TRACE command failed for $POD${NC}"
#             read -rp "Continue with this pod? [y/N]: " CONT
#             [[ "$CONT" =~ ^[Yy]$ ]] || continue
#         fi
#
#         TARGET_NAMES+=("$POD")
#         TARGET_TYPES+=("K8S_POD")
#         TRACE_COMPONENTS+=("$LWAC_COMPONENT")
#
#         sleep 1
#         SELECTED_COUNT=$((SELECTED_COUNT+1))
#     done
#
#     [ "$SELECTED_COUNT" -gt 0 ] || die "No pod selected successfully."
#
#     for i in "${!TARGET_NAMES[@]}"; do
#         POD="${TARGET_NAMES[$i]}"
#         DIR="${RUN_DIR}/K8S_$(safe_name "$POD")"
#         mkdir -p "$DIR"
#
#         echo "Starting live capture: $POD"
#         kubectl logs "$POD" --follow --all-containers=true > "$DIR/raw.log" 2>&1 &
#         PID=$!
#         TARGET_PIDS+=("$PID")
#         CAPTURE_PIDS="${CAPTURE_PIDS} ${PID}"
#
#         echo "  PID : $PID"
#         echo "  RAW : $DIR/raw.log"
#     done
#
## ###############################################################################
## AM REMOTE VM
## ###############################################################################
# elif [ "$SOURCE_CHOICE" = "2" ]; then
#
#     need_cmd ssh-copy-id
#
#     echo
#     echo "Finding AM VM host from /etc/hosts..."
#
#     AM_HOST=""
#     while read -r IP HOSTS REST; do
#         [ -n "$IP" ] || continue
#         [ -n "$HOSTS" ] || continue
#         case "$IP" in \#*) continue ;; esac
#
#         for HOST in $HOSTS $REST; do
#             case "$HOST" in \#*) break ;; esac
#             if echo "$HOST" | grep -qi 'am'; then
#                 AM_HOST="$HOST"
#                 break 2
#             fi
#         done
#     done < <(grep -v '^[[:space:]]*#' /etc/hosts | sed '/^[[:space:]]*$/d')
#
#     [ -n "$AM_HOST" ] || die "No non-commented AM host was found in /etc/hosts."
#     echo "AM host selected: $AM_HOST"
#
#     read -rp "SSH user: " AM_USER
#     [ -n "$AM_USER" ] || die "SSH user cannot be empty."
#
#     mkdir -p "${HOME}/.ssh"
#     chmod 700 "${HOME}/.ssh"
#
#     if [ ! -f "$SSH_KEY" ]; then
#         echo
#         echo "First-time passwordless SSH setup."
#         ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "ewp-am-trace" >/dev/null
#         ssh-copy-id -i "${SSH_KEY}.pub" "${AM_USER}@${AM_HOST}" ||
#             die "Unable to install SSH key on AM VM."
#     fi
#
#     SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
#
#     ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" "echo SSH_OK" |
#         grep -q SSH_OK || die "Passwordless SSH connection failed."
#
#     echo -e "${GREEN}Passwordless SSH connection successful.${NC}"
#
#     STATUS_OUTPUT="$(
#         ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" \
#         "sudo -n -su lwac lwac-control -a status | grep -i run"
#     )" || die "Unable to execute lwac-control status. Check sudo NOPASSWD permission."
#
#     [ -n "$STATUS_OUTPUT" ] || die "No Running AM instances found."
#
#     STATUS_FILE="${RUN_DIR}/am_status.txt"
#     printf '%s\n' "$STATUS_OUTPUT" |
#         sed -n 's/.*(\([^)]*\)).*/\1/p' |
#         sed '/^[[:space:]]*$/d' > "$STATUS_FILE"
#
#     echo
#     echo "Running AM instances:"
#     nl -ba "$STATUS_FILE"
#     echo
#
#     read -rp "Select one or multiple instances (example: 1 or 1,2): " AM_SELECTION
#     IFS=',' read -ra SELECTED_AM <<< "$AM_SELECTION"
#
#     for n in "${SELECTED_AM[@]}"; do
#         n="$(echo "$n" | xargs)"
#         [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid AM selection: $n"
#
#         INSTANCE="$(sed -n "${n}p" "$STATUS_FILE" | xargs)"
#         [ -n "$INSTANCE" ] || die "Invalid AM instance number: $n"
#
#         LOG_FILE="/var/log/lwac/${INSTANCE}/log/all.log"
#         LOGGING_PROPERTIES="/opt/lwac/apps/${INSTANCE}/logging.properties"
#
#         echo
#         echo "Enabling TRACE for AM instance: $INSTANCE"
#
#         ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" \
#             "sudo test -f '$LOGGING_PROPERTIES' && sudo sed -i -E 's/^[[:space:]]*com\\.ericsson\\.level=.*/com.ericsson.level=TRACE/; s/^[[:space:]]*com\\.ericsson\\.lwac\\.level=.*/com.ericsson.lwac.level=TRACE/' '$LOGGING_PROPERTIES'" ||
#             die "Unable to enable TRACE in $LOGGING_PROPERTIES"
#
#         TRACE_AM_INSTANCES+=("$INSTANCE")
#         TARGET_NAMES+=("$INSTANCE")
#         TARGET_TYPES+=("AM_VM")
#
#         DIR="${RUN_DIR}/AM_VM_$(safe_name "$INSTANCE")"
#         mkdir -p "$DIR"
#
#         ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" \
#             "sudo test -f '$LOG_FILE'" ||
#             die "Log file not found: $LOG_FILE"
#
#         echo "Starting remote live log capture..."
#         ssh "${SSH_OPTS[@]}" "${AM_USER}@${AM_HOST}" \
#             "sudo tail -n 0 -f '$LOG_FILE'" > "$DIR/raw.log" 2>&1 &
#
#         PID=$!
#         TARGET_PIDS+=("$PID")
#         CAPTURE_PIDS="${CAPTURE_PIDS} ${PID}"
#
#         echo "  PID : $PID"
#         echo "  RAW : $DIR/raw.log"
#     done
#
# else
#     die "Invalid source selection."
# fi
#
## ###############################################################################
## TESTER FLOW
## ###############################################################################
# echo
# echo "======================================================================"
# echo "LIVE LOG CAPTURE IS RUNNING"
# echo "======================================================================"
# echo
# echo "Selected targets:"
# for i in "${!TARGET_NAMES[@]}"; do
#     echo "  - ${TARGET_TYPES[$i]} : ${TARGET_NAMES[$i]}"
# done
# echo
# echo "Ask the tester to perform the complete transaction now."
# echo "Do NOT enter search values until the transaction is complete."
# echo
#
# read -rp "Has the tester completed the transaction? [y/N]: " DONE
# [[ "$DONE" =~ ^[Yy]$ ]] || die "Transaction not confirmed."
#
# echo
# echo "Enter search value(s), comma separated."
# echo "Examples:"
# echo "  2290146161719"
# echo "  2290146161719,getproductlist"
# echo "  2290146161719,1104,FAILURE"
# echo "  thread-id,ERROR"
# echo "  transaction-id"
# echo
# read -rp "Search value(s): " SEARCH_INPUT
#
# echo
# echo "Enter additional log capture time in seconds."
# while true; do
#     read -rp "Additional log capture time [10]: " POST_TRANSACTION_WAIT
#     POST_TRANSACTION_WAIT="${POST_TRANSACTION_WAIT:-10}"
#     [[ "$POST_TRANSACTION_WAIT" =~ ^[0-9]+$ ]] && break
#     echo "Invalid value. Please enter a whole number of seconds."
# done
#
# echo
# echo "Waiting ${POST_TRANSACTION_WAIT} seconds for remaining logs..."
# for ((i=POST_TRANSACTION_WAIT; i>0; i--)); do
#     printf "\rRemaining: %02d seconds" "$i"
#     sleep 1
# done
# echo
#
# echo
# echo "Stopping live captures..."
# for PID in "${TARGET_PIDS[@]}"; do
#     kill "$PID" 2>/dev/null || true
# done
# sleep 2
# for PID in "${TARGET_PIDS[@]}"; do
#     kill -9 "$PID" 2>/dev/null || true
# done
# CAPTURE_PIDS=""
#
# echo
# echo "======================================================================"
# echo "TRACE DISABLE OPTION"
# echo "======================================================================"
# echo "Do you want to disable TRACE now?"
# echo "  Y/y = Disable TRACE"
# echo "  N/n or any other value = Keep TRACE enabled"
# echo
# read -rp "Disable TRACE? [y/N]: " DISABLE_TRACE_CHOICE
# if [[ "$DISABLE_TRACE_CHOICE" =~ ^[Yy]$ ]]; then
#     disable_traces
#     echo "TRACE has been disabled for the selected target(s)."
# else
#     echo "TRACE will remain enabled for the selected target(s)."
# fi
#
## ###############################################################################
## PYTHON PARSER
## ###############################################################################
# PARSER="${RUN_DIR}/ewp_parser.py"
#
# cat > "$PARSER" <<'PY'
# import sys
# import os
# import re
# import csv
# from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
#
# root = sys.argv[1]
# search_input = sys.argv[2] if len(sys.argv) > 2 else ""
# search_terms = [x.strip() for x in search_input.split(",") if x.strip()]
#
# HEAD_RE = re.compile(
#     r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}[.,]\d+\s+"
#     r"(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s+(\S+)\s+\S+\s+-\s+(.*)$",
#     re.I
# )
# TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d+[.,]\d+")
#
# def clean(v):
#     return re.sub(r"\s+", " ", str(v or "").replace("\r", " ").replace("\n", " ")).strip()
#
# def mask_credentials(text):
#     if not text:
#         return ""
#     def mask_url(m):
#         url = m.group(0)
#         try:
#             p = urlsplit(url)
#             pairs = parse_qsl(p.query, keep_blank_values=True)
#             masked = []
#             for k, v in pairs:
#                 if k.lower() in {"password","passwd","pwd","secret","clientsecret","client_secret","token"}:
#                     v = "********"
#                 masked.append((k, v))
#             return urlunsplit((p.scheme,p.netloc,p.path,urlencode(masked),p.fragment))
#         except Exception:
#             return re.sub(r"(?i)(password|passwd|pwd|secret|token)=([^&\s]+)", r"\1=********", url)
#     text = re.sub(r"https?://[^\s<>]+", mask_url, text)
#     text = re.sub(r"(?is)(<password>).*?(</password>)", r"\1********\2", text)
#     text = re.sub(r"(?i)(password\s*[:=]\s*)[^,\s&]+", r"\1********", text)
#     return text
#
# def parse_header(line):
#     m = HEAD_RE.match(line)
#     if not m:
#         return "", ""
#     ts = line[:23]
#     return ts, m.group(1)
#
# def search_in_text(text):
#     if not search_terms:
#         return True
#     low = text.lower()
#     return any(term.lower() in low for term in search_terms)
#
# def first_match(text):
#     for term in search_terms:
#         if term.lower() in text.lower():
#             return term
#     return ""
#
# def parse_thread(thread_id, lines, target_name, target_type):
#     block = "\n".join(lines)
#
#     if not search_in_text(block):
#         return []
#
#     timestamp = ""
#     for line in lines:
#         ts, _ = parse_header(line)
#         if ts:
#             timestamp = ts
#             break
#
#     inbound_api = ""
#     context = ""
#     inbound_method = ""
#     inbound_url = ""
#     inbound_request = []
#     ewp_response = []
#     threedpp_url = ""
#     threedpp_method = ""
#     threedpp_request = []
#     threedpp_response = []
#     errors = []
#     transaction_id = ""
#
#     mode = None
#     current_response_source = None
#
#     for line in lines:
#         m = re.search(
#             r"HTTP\s+(GET|POST|PUT|DELETE|PATCH)\s+"
#             r"/(?:serviceprovider|bceao)/([^/\s]+)/([A-Za-z0-9_.-]+)",
#             line, re.I
#         )
#         if m and "HTTP Response for" not in line:
#             inbound_method = m.group(1).upper()
#             context = m.group(2)
#             inbound_api = m.group(3)
#             continue
#
#         m = re.search(
#             r"HTTP\s+(GET|POST|PUT|DELETE|PATCH)\s+to\s+(\S+)",
#             line, re.I
#         )
#         if m:
#             if "HttpClientImpl" in line:
#                 threedpp_method = m.group(1).upper()
#                 threedpp_url = m.group(2)
#             continue
#
#         m = re.search(
#             r"Request\s+is\s+built,\s+HTTP\s+"
#             r"(GET|POST|PUT|DELETE|PATCH)\s+to\s+(\S+)",
#             line, re.I
#         )
#         if m:
#             threedpp_method = m.group(1).upper()
#             threedpp_url = m.group(2)
#             threedpp_request.append(line)
#             mode = "3PP_REQUEST"
#             continue
#
#         if re.search(r"HttpServerImpl\s+-\s+Request\s*$", line, re.I):
#             mode = "EWP_REQUEST"
#             continue
#
#         if re.search(r"HttpClientImpl\s+-\s+Response\s*$", line, re.I):
#             mode = "3PP_RESPONSE"
#             continue
#
#         if re.search(r"HttpServerImpl\s+-\s+Response\s*$", line, re.I):
#             mode = "EWP_RESPONSE"
#             continue
#
#         m = re.search(r"Created main transaction\s+(\S+)", line, re.I)
#         if m:
#             transaction_id = m.group(1)
#
#         if "HTTP Response for" in line:
#             continue
#
#         if HEAD_RE.match(line):
#             continue
#
#         if mode == "EWP_REQUEST":
#             inbound_request.append(line)
#         elif mode == "3PP_REQUEST":
#             if line.strip():
#                 threedpp_request.append(line)
#         elif mode == "3PP_RESPONSE":
#             if line.strip():
#                 threedpp_response.append(line)
#         elif mode == "EWP_RESPONSE":
#             if line.strip():
#                 ewp_response.append(line)
#
#         if re.search(
#             r"UNAUTHORIZED|Authentication Failed|Failed to Authenticate|"
#             r"\bERROR\b|Exception|failed|failure|timeout|timed out|"
#             r"VALIDATION_ERROR|FAULT|SOAP Fault",
#             line, re.I
#         ):
#             errors.append(line)
#
#     def uniq_clean(items):
#         out = []
#         seen = set()
#         for x in items:
#             x = x.strip()
#             if not x:
#                 continue
#             k = x
#             if k not in seen:
#                 seen.add(k)
#                 out.append(x)
#         return out
#
#     inbound_request = uniq_clean(inbound_request)
#     threedpp_request = uniq_clean(threedpp_request)
#     threedpp_response = uniq_clean(threedpp_response)
#     ewp_response = uniq_clean(ewp_response)
#     errors = uniq_clean(errors)
#
#     request_text = clean("\n".join(inbound_request))
#     if threedpp_request:
#         request_text += (" | 3PP REQUEST: " if request_text else "3PP REQUEST: ")
#         request_text += clean("\n".join(threedpp_request))
#
#     response_text = clean("\n".join(threedpp_response))
#     if ewp_response:
#         response_text += (" | EWP RESPONSE: " if response_text else "EWP RESPONSE: ")
#         response_text += clean("\n".join(ewp_response))
#
#     error_text = clean(" | ".join(errors))
#
#     combined = f"{response_text} {error_text}"
#     status = "FAILED" if re.search(
#         r"<status>\s*FAILURE|responseCode>\s*(?!0\b)\d+|"
#         r"Failed to Authenticate|Authentication Failed|"
#         r"VALIDATION_ERROR|\bfailure\b|\bfailed\b",
#         combined, re.I
#     ) else "SUCCESS"
#
#     if not (inbound_api or threedpp_url or request_text or response_text or error_text):
#         return []
#
#     ms = re.search(r"<msisdn>\s*([^<\s]+)\s*</msisdn>", block, re.I)
#     msisdn = ms.group(1) if ms else ""
#     if not msisdn:
#         ms = re.search(r"(?:[?&]msisdn=)([^&\s]+)", block, re.I)
#         msisdn = ms.group(1) if ms else ""
#
#     api_name = inbound_api
#     if not api_name and threedpp_url:
#         path = urlsplit(threedpp_url).path.rstrip("/")
#         api_name = path.split("/")[-1] if path else ""
#
#     return [[
#         timestamp,
#         thread_id,
#         first_match(block),
#         msisdn,
#         api_name,
#         context,
#         "EWP+3PP" if threedpp_url else "EWP",
#         inbound_method or threedpp_method,
#         mask_credentials(request_text),
#         mask_credentials(threedpp_url),
#         mask_credentials(response_text),
#         status,
#         mask_credentials(error_text),
#         transaction_id,
#         target_name,
#         target_type
#     ]]
#
# def parse_target(path, target_name, target_type):
#     raw = os.path.join(path, "raw.log")
#     if not os.path.exists(raw):
#         return []
#
#     with open(raw, encoding="utf-8", errors="replace") as f:
#         lines = [x.rstrip("\n") for x in f]
#
#     threads = {}
#     current_thread = ""
#     for line in lines:
#         ts, th = parse_header(line)
#         if th:
#             current_thread = th
#             threads.setdefault(current_thread, [])
#         if current_thread:
#             threads[current_thread].append(line)
#
#     records = []
#     for thread_id, thread_lines in threads.items():
#         records.extend(parse_thread(thread_id, thread_lines, target_name, target_type))
#     return records
#
# headers = [
#     "Timestamp","Thread ID","Search Match","MSISDN","API Name","Context",
#     "Direction","Method","Request","3PP URL","Response","Status","Error",
#     "Transaction ID","Target","Source"
# ]
#
# all_records = []
# for name in os.listdir(root):
#     if not name.startswith(("K8S_", "AM_VM_")):
#         continue
#     p = os.path.join(root, name)
#     if os.path.isdir(p):
#         source = "K8S_POD" if name.startswith("K8S_") else "AM_VM"
#         target = name.split("_", 1)[1]
#         all_records.extend(parse_target(p, target, source))
#
# csv_path = os.path.join(root, "combined_api_trace.csv")
# with open(csv_path, "w", newline="", encoding="utf-8") as f:
#     w = csv.writer(f)
#     w.writerow(headers)
#     w.writerows(all_records)
#
# for name in os.listdir(root):
#     if not name.startswith(("K8S_", "AM_VM_")):
#         continue
#     p = os.path.join(root, name)
#     if not os.path.isdir(p):
#         continue
#     target = name.split("_", 1)[1]
#     rows = [r for r in all_records if r[14] == target]
#     with open(os.path.join(p, "api_trace.csv"), "w", newline="", encoding="utf-8") as f:
#         w = csv.writer(f)
#         w.writerow(headers)
#         w.writerows(rows)
#
# try:
#     from openpyxl import Workbook
#     from openpyxl.styles import Font, Alignment
#
#     def write_xlsx(path, rows):
#         wb = Workbook()
#         ws = wb.active
#         ws.title = "API Trace"
#         ws.append(headers)
#         for c in ws[1]:
#             c.font = Font(bold=True)
#         for r in rows:
#             ws.append(r)
#         ws.freeze_panes = "A2"
#         ws.auto_filter.ref = ws.dimensions
#         widths = [24,42,24,20,35,24,14,10,100,100,100,14,80,25,35,15]
#         for i,w in enumerate(widths,1):
#             n=i; s=""
#             while n:
#                 n, rem = divmod(n-1,26)
#                 s=chr(65+rem)+s
#             ws.column_dimensions[s].width=w
#         for row in ws.iter_rows():
#             for c in row:
#                 c.alignment=Alignment(vertical="top", wrap_text=True)
#         wb.save(path)
#
#     write_xlsx(os.path.join(root,"combined_api_trace.xlsx"), all_records)
#     for name in os.listdir(root):
#         if name.startswith(("K8S_","AM_VM_")) and os.path.isdir(os.path.join(root,name)):
#             target=name.split("_",1)[1]
#             rows=[r for r in all_records if r[14]==target]
#             if rows:
#                 write_xlsx(os.path.join(root,name,"api_trace.xlsx"), rows)
# except ImportError:
#     pass
#
# print("Records generated:", len(all_records))
# print("CSV:", csv_path)
#
# PY
#
## ###############################################################################
## RUN PARSER
## ###############################################################################
# echo
# echo "======================================================================"
# echo "Parsing captured logs"
# echo "======================================================================"
# echo "Search value(s): ${SEARCH_INPUT:-<none - parse all>}"
# echo
#
# if command -v python3 >/dev/null 2>&1; then
#     python3 "$PARSER" "$RUN_DIR" "$SEARCH_INPUT"
# else
#     echo -e "${YELLOW}Python3 not installed. Raw logs are available, but CSV/XLSX parsing was skipped.${NC}"
# fi
#
# echo
# echo "======================================================================"
# echo "CAPTURE COMPLETED"
# echo "======================================================================"
# echo
# echo "Search value(s) : $SEARCH_INPUT"
# echo "Run directory   : $RUN_DIR"
# echo
# echo "Generated files:"
# find "$RUN_DIR" -maxdepth 2 -type f -print 2>/dev/null
# echo
# echo "Combined reports:"
# echo "  $RUN_DIR/combined_api_trace.csv"
# echo "  $RUN_DIR/combined_api_trace.xlsx"
# echo
# END_EWP_BASH