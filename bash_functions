# Expected environment variables:

# export _CODEFRESH_TOKEN=
# export _TF_TOKEN=
# export _TENV_AUTO_INSTALL=
# export _OPSLEVEL_API_TOKEN=
# export SLACK_TOKEN=
# export SLACK_SIGNING_SECRET=
# export _DD_CLIENT_API_KEY=
# export _DD_CLIENT_APP_KEY=
# export AZURE_SUBSCRIPTION_DEV_ID=
# export AZURE_SUBSCRIPTION_PRD_ID=
# export AZURE_SC_RG_PREFIX=
# export AZURE_SC_CLUSTER_PREFIX=

codefresh_auth () {
  export CODEFRESH_TOKEN=$_CODEFRESH_TOKEN
  export CF_KEY=$CODEFRESH_TOKEN
  export CF_API_KEY=$CODEFRESH_TOKEN
}

git-clone () {
  cd ~/repos
  git clone $1
  cd `echo $1 | cut -d'/' -f2 | cut -d'.' -f1`
}

tf-login () {
  export TF_TOKEN=$_TF_TOKEN
}

ops-auth () {
  export OPSLEVEL_API_TOKEN=$_OPSLEVEL_API_TOKEN
}

# MAC specific functions
ss () {
  sudo lsof -i -P | grep LISTEN | grep :$PORT | grep IPv4 $@
}

ss-ipv6 () {
  sudo lsof -i -P | grep LISTEN | grep :$PORT | grep IPv6 $@
}

datadog-auth () {
  export DD_CLIENT_API_KEY=$_DD_CLIENT_API_KEY
  export DD_CLIENT_APP_KEY=$_DD_CLIENT_APP_KEY
}

k () {
  kubectl $@
}
generate_password() {
  local password_length=${1:-"16"}
  echo -e "Generating a random password with ${password_length} characters: Use \`generate_password [length]\` to specify length.\n"
  echo -n "password: "; LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*_-' < /dev/urandom | head -c $password_length && echo
}

_az_login () {
  trap "az config set core.login_experience_v2=on &>/dev/null" EXIT HUP INT QUIT PIPE TERM
  az account set --subscription $1 &>/dev/null
  if [ $? -ne 0 ]; then
    az config set core.login_experience_v2=off &>/dev/null
    az login &>/dev/null
    if [ $? -ne 0 ]; then
      echo "Azure login failed"
      return 1
    fi
  fi
  az account set --subscription $1 &>/dev/null
}

_aks-login () {
  _az_login $3
  if [ $? -ne 0 ]; then
    echo "AKS login failed"
    return 1
  fi
  az aks get-credentials --resource-group $1 --name $2 --overwrite-existing
}

aks-sc-login () {
  case "$1" in
    "dev")
      _aks-login ${AZURE_SC_RG_PREFIX}-dev-1 ${AZURE_SC_CLUSTER_PREFIX}-dev-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    "prd"|"prod")
      _aks-login ${AZURE_SC_RG_PREFIX}-prod-1 ${AZURE_SC_CLUSTER_PREFIX}-prod-1 $AZURE_SUBSCRIPTION_PRD_ID
      return
      ;;
    "prddr"|"proddr")
      _aks-login ${AZURE_SC_RG_PREFIX}-prod-dr-1 ${AZURE_SC_CLUSTER_PREFIX}-prod-dr-1 $AZURE_SUBSCRIPTION_PRD_ID
      return
      ;;
    "test")
      _aks-login ${AZURE_SC_RG_PREFIX}-test-1 ${AZURE_SC_CLUSTER_PREFIX}-test-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    "uat")
      _aks-login ${AZURE_SC_RG_PREFIX}-uat-1 ${AZURE_SC_CLUSTER_PREFIX}-uat-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    *)
      echo "Usage: aks-sc-login [dev|prd|prddr|test|uat]"
      return 1
      ;;
  esac
}

gen-xkcd-pass() {
  [ $(echo "$1"|grep -E "[0-9]+") ] && NUM="$1" || NUM=1
  DICT=$(LC_CTYPE=C grep -E "^[a-zA-Z]{3,6}$" /usr/share/dict/words)
  for I in $(seq 1 "$NUM"); do
      WORDS=$(echo "$DICT"|gshuf -n 6|paste -sd ' ' -)
      XKCD=$(echo "$WORDS"|sed 's/ //g')
      echo "$XKCD ($WORDS)"|awk '{x=$1;$1="";printf "%-36s %s\n", x, $0}'
  done | column
}

_k-decode-secret () {
  secrets=`echo $1 | base64 -d`
  for s in $secrets; do
    key=`echo $s | cut -d',' -f1`
    hash=`echo $s | cut -d',' -f2`
    echo "$key: `echo $hash | base64 -d`"
  done
}

k-decode-secret () {
  SECRET=$1
  START_WITH=$2
  if [ -z "$SECRET" ]; then
    echo "Usage: k-decode-secret <secret-name> [keys-starts-with]"
    exit 1
  fi
  if [ -z "$START_WITH" ]; then
    _k-decode-secret `kubectl get secret $SECRET -o json | jq -r '.data | to_entries | .[] | [.key, .value] | join(",")' | base64 -b0`
    return
  fi
  _k-decode-secret `kubectl get secret $SECRET -o json | jq -r --arg s "$START_WITH" '.data | with_entries(select(.key | startswith($s))) | to_entries | .[] | [.key, .value] | join(",")' | base64 -b0`
}