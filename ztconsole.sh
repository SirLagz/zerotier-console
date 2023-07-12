#!/bin/bash -i
ZTCVERSION="ZeroTier Console v0.01.1"
REMOTEONLY=0
NONC=0

if [[ ! $(whoami) == "root" ]]; then
    echo "This program requires root access. Please login as root or run with sudo"
    exit
fi

if [[ ! $(command -v jq) ]]; then
    echo "jq not found. Please install jq before running this program"
    exit
fi

if [[ ! $(command -v curl) ]]; then
    echo "curl not found. Please install curl before running this program"
    exit
fi

if [[ ! $(command -v whiptail) ]]; then
    echo "whiptail not found. Please install whiptail before running this program"
    exit
fi

if [[ ! $(command -v nc) ]]; then
    NONC=1
    whiptail --title "ZeroTier Console" --msgbox "nc not found. Controller and Token status will be inaccurate" 30 80
fi

if [[ ! $(command -v zerotier-cli) ]]; then
    whiptail --title "ZeroTier Console" --msgbox "zerotier-cli not found. Local Zerotier Options unavailable." 30 80
    REMOTEONLY=1
fi

if [ -n "$COLUMNS" ] && [[ COLUMNS -gt 48 ]] ; then
        WTW=$((COLUMNS-8))
else
        WTW=80
fi

if [ -n "$LINES" ] && [[ LINES -gt 38 ]]; then
        WTH=$((LINES-8))
else
        WTH=30
fi

TOKEN=""
NODEINFO=""
NODEADDRESS=""
TITLE="$ZTCVERSION"
MEMSTATUS=""
CONFFILE="ztconsole.json"
TOKENPATH="/var/lib/zerotier-one/"
TOKENFILE="authtoken.secret"

CONTROLLERIP="localhost"
CONTROLLERPORT="9993"
CONTROLLERTOKEN=""
CONTSTATUS=""

function wtMsgBox() {
    whiptail --title "$TITLE" --msgbox "$1" $WTH $WTW
}

function wtInfoMsgBox() {
    whiptail --title "$TITLE" --msgbox "$1" 40 80 --scrolltext
}

function wtTextInput() {
    textInput=$(whiptail --title "$TITLE" --inputbox "$1" $WTH $WTW "$2" 3>&1 1>&2 2>&3)
    echo $textInput
}

function wtConfirm() {
    whiptail --title "$TITLE" --yesno "$1" $WTH $WTW
    return $?
}

function curlGetHTTPCode() {
    curlOut=$1
    code="${curlOut:${#curlOut}-3}"
    echo $code
}

function curlGetHTTPOut() {
    curlOut=$1
    out="${curlOut:0:${#curlOut}-3}"
    echo $out
}

function getConfig() {
   if [[ -f "$CONFFILE" ]]; then
       jsonCurrentConf=$(jq -r . $CONFFILE)

       CONTROLLERIP=$(echo $jsonCurrentConf | jq -r .Controller)
       if [ -e $(echo "$CONTROLLERIP" | grep -i -P '^(0{0,2}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)(\.(?!$)|$)){4}$|^([a-z0-9]([-a-z0-9\.]*[a-z0-9])?)$') ]; then
           wtMsgBox "Invalid IP address confgured. Please check IP address."
       fi

       CONTROLLERPORT=$(echo $jsonCurrentConf | jq -r .Port)
       if [[ CONTROLLERPORT -lt 1 ]] || [[ CONTROLLERPORT -gt 65535 ]]; then
           wtMsgBox "Invalid Port configured.  Please check port."
       fi

       CONTROLLERTOKEN=$(echo $jsonCurrentConf | jq -r .Token)
       if [ -e $(echo "$CONTROLLERTOKEN" | grep -P '^[a-z0-9]{24}$' - <<< "$CONTROLLERTOKEN") ]; then
           wtMsgBox "Invalid Token configured.  Please check token."
       fi
   fi
}

function getAuth() {
    getConfig
    if [[ $CONTROLLERTOKEN == "" ]]; then
        if [[ -f "$TOKENPATH$TOKENFILE" ]]; then
            TOKEN=$(cat $TOKENPATH$TOKENFILE)
            NODEINFO=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/status" -H "X-ZT1-AUTH: ${TOKEN}")
            NODEADDRESS=$(echo $NODEINFO | jq -r .address)
            TITLE="$ZTCVERSION : $NODEADDRESS"
        else
            wtMsgBox "Token not found. Please check token path and filename or set one in ZeroTier Console settings"
            exit
        fi
    else
        TOKEN=$CONTROLLERTOKEN
    fi
}

function menuMain() {

    echo yes | nc -w 1 $CONTROLLERIP $CONTROLLERPORT
    if [[ $? -eq 0 ]]; then
        CONTSTATUS="Controller Reachable"
    else
        CONTSTATUS="*** CONTROLLER UNREACHABLE ***"
    fi
    if [[ ${#TOKEN} -eq 0 ]]; then
        CONTTOKENSTATUS="*** EMPTY TOKEN ***"
    elif [[ ! ${#TOKEN} -eq 24 ]]; then
        CONTTOKENSTATUS="*** INVALID TOKEN ***"
    else
        if [[ $CONTSTATUS == "Controller Reachable" ]] || [[ $NONC -eq 1 ]]; then
            tokenTestConnect=$(curl -w "%{http_code}" -s "http://$CONTROLLERIP:$CONTROLLERPORT/status" -H "X-ZT1-AUTH: ${TOKEN}")
            http_code="${tokenTestConnect:${#tokenTestConnect}-3}"
            if [[ $http_code -eq "200" ]]; then
                CONTTOKENSTATUS="Token OK"
                jsonBody="${tokenTestConnect:0:${#tokenTestConnect}-3}"
                NODEADDRESS=$(echo $jsonBody | jq -r .address)
                TITLE="$ZTCVERSION : $NODEADDRESS"
            elif [[ $http_code -eq "000" ]]; then
                CONTTOKENSTATUS="*** COMMUNICATION PROBLEM ***"
            else
                CONTTOKENSTATUS="*** TOKEN NOT AUTHORISED ***"
           fi
        else
            CONTTOKENSTATUS="*** CONTROLLER UNREACHABLE ***"
        fi
    fi

    if [[ $REMOTEONLY -eq 1 ]]; then
        menuItems=(Controller "Information and Configuration"
Settings "ZeroTier Console Settings"
)
    elif [[ ! $CONTTOKENSTATUS == "Token OK" ]] && [[ $NONC -eq 0 ]]; then
       menuItems=("Client" "Information and Configuration"
Settings "ZeroTier Console Settings"
)
    else
        menuItems=("Client" "Information and Configuration"
Controller "Information and Configuration"
Settings "ZeroTier Console Settings"
)
    fi


    menuText="ZeroTier Console
Controller IP: $CONTROLLERIP
Controller Port: $CONTROLLERPORT
Controller Connection Status: $CONTSTATUS
Token Status: $CONTTOKENSTATUS"

    menuMainSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Exit --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        exit
    fi
    case $menuMainSelect in
        Client)
            menuThisNode
        ;;
        Controller)
            menuController
        ;;
        Networks)
            menuNetworks
        ;;
        Settings)
            menuZTCSettings
        ;;
        Clients)
            menuClients
        ;;
    esac
    exit
}

function createZTCConf() {
    echo '{"Controller":"'"$CONTROLLERIP"'","Port":"'"$CONTROLLERPORT"'","Token":"'"$CONTROLLERTOKEN"'"}' | jq -c > "$CONFFILE"
    chmod 600 "$CONFFILE"
}

function ZTCContIP() {
    if [[ ! -f "$CONFFILE" ]]; then
        wtMsgBox "Config file not found. Creating $CONFFILE"
        createZTCConf
    fi
    jsonCurrentConf=$(jq -r . $CONFFILE)
    jsonCurrentIP=$(echo $jsonCurrentConf | jq -r .Controller)
    input=$(wtTextInput "Please enter controller IP or Hostname" $jsonCurrentIP)
    jsonNewIP=$(echo $jsonCurrentConf | jq '. | .Controller |= "'"$input"'"')
    echo $jsonNewIP | jq -c > "$CONFFILE"
    CONTROLLERIP="$input"
    wtMsgBox "Updated controller to $input"
    menuZTCSettings
}

function ZTCContPort() {
    if [[ ! -f "$CONFFILE" ]]; then
        wtMsgBox "Config file not found. Creating $CONFFILE"
        createZTCConf
    fi
    jsonCurrentConf=$(jq -r . $CONFFILE)
    jsonCurrentPort=$(echo $jsonCurrentConf | jq -r .Port)
    input=$(wtTextInput "Please enter controller port" $jsonCurrentPort)
    jsonNewPort=$(echo $jsonCurrentConf | jq '. | .Port |= "'"$input"'"')
    echo $jsonNewPort | jq -c > "$CONFFILE"
    CONTROLLERPORT="$input"
    wtMsgBox "Updated controller port to $input"
    menuZTCSettings
}

function ZTCAuth() {
    if [[ ! -f "$CONFFILE" ]]; then
        wtMsgBox "Config file not found. Creating $CONFFILE"
        createZTCConf
    fi
    jsonCurrentConf=$(jq -r . $CONFFILE)
    jsonCurrentToken=$(echo $jsonCurrentConf | jq -r .Token)
    input=$(wtTextInput "Please enter controller authentication token" $jsonCurrentToken)
    jsonNewToken=$(echo $jsonCurrentConf | jq '. | .Token |= "'"$input"'"')
    echo $jsonNewToken | jq -c > "$CONFFILE"
    CONTROLLERTOKEN="$input"
    TOKEN="$input"
    wtMsgBox "Updated controller authentication token to $input"
    menuZTCSettings
}

function menuZTCSettings() {
    menuItems=("Controller IP" "Set Custom Controller IP Address"
"Controller Port" "Set Custom Controller Port"
"Auth Token" "Set Token"
)
    menuText="Change settings for ZeroTier Console"

    menuZTCSettingsSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}"  3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuMain
        exit
    fi
    case $menuZTCSettingsSelect in
        "Controller IP")
            ZTCContIP
        ;;
        "Controller Port")
            ZTCContPort
        ;;
        "Auth Token")
            ZTCAuth
        ;;
    esac
    exit
}

function menuController() {
    menuItems=(Info "Show Controller Info"
Networks "View and configure networks")
    menuText="ZeroTier Controller Console"
    menuControllerSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}"  3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuMain
        exit
    fi

    case $menuControllerSelect in
        Info)
            infoController
        ;;
        Networks)
            menuNetworks
        ;;
    esac
}

function infoController() {
    jsonControllerInfo=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller" -H "X-ZT1-AUTH: ${TOKEN}")
    wtInfoMsgBox "$jsonControllerInfo"
    menuController
}

function menuThisNode() {
menuItems=(Info "About This Node"
Join "this node to a network"
Leave "a network this node is connected to"
)

    menuClientSelect=$(whiptail --title "$TITLE" --menu "ZeroTier Client Console" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuMain
        exit
    fi

    case $menuClientSelect in
        Info)
            thisNodeInfo
        ;;
        Join)
            cmenuJoinNetwork
        ;;
        Leave)
            cmenuLeaveNetwork
        ;;
    esac
}

function cmenuLeaveNetwork() {
    menuItems=()
    jsonJoinedNetworks=$(zerotier-cli -j listnetworks | jq)
    IFS=$'\n' read -rd '' -a arrJoinedNetworks <<< $(echo $jsonJoinedNetworks | jq '.[] | (.id,.name)')
    for i in "${arrJoinedNetworks[@]}"; do
        menuItems+=("  $i")
    done
    menuText="ZeroTier Client Console\nLeave a network"
    menuNetworkSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}"  3>&1 1>&2 2>&3)
    if [[ $? -gt 0 ]]; then
        menuThisNode
    fi
    menuNetworkSelect=$(echo $menuNetworkSelect | xargs)
    if [[ ${#menuNetworkSelect} -eq 16 ]]; then
        jsonLeaveNetwork=$(zerotier-cli leave $menuNetworkSelect)
        wtMsgBox "Left Network $jsonLeaveNetwork"
    else
        wtMsgBox "Invalid Network ID $jsonLeaveNetwork"
    fi
    menuThisNode
}

function cmenuJoinNetwork() {
    menuItems=(Enter "in a network id to join"
List "local Controller networks to join"
)
    menuText="ZeroTier Client Console\nJoin a network"
    menuClientSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -gt 0 ]]; then
        menuThisNode
    fi
    case $menuClientSelect in
    Enter)
        clientJoinID
    ;;
    List)
        clientJoinLAN
    ;;
    esac
}
function clientJoinID() {
    txtNetworkID=$(whiptail --title "$TITLE" --inputbox "Enter in Network ID" $WTH $WTW 3>&1 1>&2 2>&3)
    if [[ $? -gt 0 ]]; then
        cmenuJoinNetwork
    fi
    if [[ ${#txtNetworkID} -ne 16 ]]; then
        wtMsgBox "Invalid Network ID"
        clientJoinID
    fi
    clientJoinNetwork  $txtNetworkID
}


function clientJoinLAN {
    jsonNetworkList=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/" -H "X-ZT1-AUTH: ${TOKEN}" )
    Networks=($(echo $jsonNetworkList | jq -r '.[]'))
    if [[ ${#Networks} -eq 0 ]]; then
        wtMsgBox "No Networks found. Please create a network"
        cmenuJoinNetwork
    fi
    miNetworks=()
    miNetworkItem=""
    for i in ${Networks[@]}; do
        boolAlreadyJoined=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/{$i}/member" -H "X-ZT1-AUTH: ${TOKEN}" | jq '. | has("'"$NODEADDRESS"'")')
        if [[ $boolAlreadyJoined == "false" ]]; then
            miNetworks+=("$i")
            jsonNetworkName=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/{$i}" -H "X-ZT1-AUTH: ${TOKEN}" | jq -r .name)
            if [[ $jsonNetworkName ]]; then
                miNetworkName="$jsonNetworkName"
            else
                miNetworkName="-"
            fi
            miNetworks+=("  ($miNetworkName) ")
        fi
    done
    menuNetworkList=$(whiptail --title "$TITLE" --menu "ZeroTier Network List\nChoose a Network Below:" $WTH $WTW 8 --cancel-button Back --ok-button Select "${miNetworks[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        cmenuJoinNetwork
        exit
    fi

    if [[ ${#menuNetworkList} -ne 16  ]]; then
        wtMsgBox "Error selecting Network. Please try again"
        cmenuJoinNetwork
        exit
    else
        clientJoinNetwork $menuNetworkList
        exit
    fi

}

function clientJoinNetwork {
    networkID=$1
    whiptail --msgbox "joining $networkID" $WTH $WTW
#    jsonJoinNetwork=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/network/{networkID}" -H "X-ZT1-AUTH: ${TOKEN}")
    jsonJoinNetwork=$(zerotier-cli join $networkID) 
   whiptail --msgbox "$jsonJoinNetwork" $WTH $WTW

    menuMain
}
function thisNodeInfo() {
    NODEINFO=$(zerotier-cli -j info | jq)
    NODEADDRESS=$(echo $NODEINFO | jq .address)
    NODEONLINE=$(echo $NODEINFO | jq .online)
    NODEVERSION=$(echo $NODEINFO | jq .version)
    NODETCPFALLBACK=$(echo $NODEINFO | jq .tcpFallbackActive)
    NODEPUBID=$(echo $NODEINFO | jq .publicIdentity)
    NODEWORLDID=$(echo $NODEINFO | jq .planetWorldId)
    NODEWORLDTS=$(echo $NODEINFO | jq .planetWorldTimestamp)


    NODESETTINGS=$(echo $NODEINFO | jq .config.settings)
    NODELISTEN=$(echo $NODESETTINGS | jq .listeningOn[])
    NODELISTEN=$(echo "${NODELISTEN//$'\n'/ }")
    NODEALLOWTCPFALLBACKRELAY=$(echo $NODESETTINGS | jq .allowTcpFallbackRelay)
    NODEFORCETCPRELAY=$(echo $NODESETTINGS | jq .forceTcpRelay)
    NODEPORTMAPPING=$(echo $NODESETTINGS | jq .portMappingEnabled)
    NODEPRIMARYPORT=$(echo $NODESETTINGS | jq .primaryPort)
    NODESECONDARYPORT=$(echo $NODESETTINGS | jq .secondaryPort)
    NODESOFTWAREUPDATE=$(echo $NODESETTINGS | jq .softwareUpdate)
    NODESOFTWARECHANNEL=$(echo $NODESETTINGS | jq .softwareUpdateChannel)
    NODETERTIARYPORT=$(echo $NODESETTINGS | jq .tertiaryPort)
    NODESURFACEADDRESS=$(echo $NODESETTINGS | jq .surfaceAddresses[])
    NODESURFACEADDRESS=$(echo "${NODESURFACEADDRESS//$'\n'/ }")


    DATA="Node Information
Node Address:   -$NODEADDRESS
Node Online:   -$NODEONLINE
Node Version:   -$NODEVERSION
Node TCP Fallback:   -$NODETCPFALLBACK
Node World ID:   -$NODEWORLDID
Node World Timestamp:   -$NODEWORLDTS
Node Public ID:   -$NODEPUBID

Node Configuration
Allow TCP Fallback Relay:   -$NODEALLOWTCPFALLBACKRELAY
Force TCP Relay:   -$NODEFORCETCPRELAY
Listening Addresses/Ports:   -$NODELISTEN
Port Mapping Enabled:   -$NODEPORTMAPPING
Primary Port:   -$NODEPRIMARYPORT
Secondary Port:   -$NODESECONDARYPORT
Software Update:   -$NODESOFTWAREUPDATE
Software Update Channel:   -$NODESOFTWARECHANNEL
Tertiary Port:   -$NODETERTIARYPORT
Surface Addresses:   -$NODESURFACEADDRESS
"


    whiptail --title "$TITLE" --msgbox "$(column -L -t -R 1 -s \- <<< $DATA)" 40 80
    menuThisNode
}

function networkCreate() {
    whiptail --title "$TITLE" --yesno "Do you want to configure the network now?" $WTH $WTW
    if [[ $? -eq 1 ]]; then
        jsonNewNetwork=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NODEADDRESS}______" -H "X-ZT1-AUTH: ${TOKEN}" -d {})
        if [[ ! $jsonNewNetwork == '{}' ]]; then 
            NWID=$(echo $jsonNewNetwork | jq -r .id)
            wtMsgBox "Network $NWID created"
            menuNetworks
            exit
        else
            wtMsgBox "Unable to create Network"
            menuNetworks
            exit
        fi
    else
        txtNetName=$(wtTextInput "Enter a Network Name")
        if [[ $? -gt 0 ]] || [[ $txtNetName == "" ]]; then
            menuNetworks
            exit
        fi
        txtIPStart=$(wtTextInput "Enter a starting IP for network range")
        if [[ $? -gt 0 ]] || [[ $txtIPStart == "" ]]; then
            menuNetworks
            exit
        fi
        txtIPEnd=$(wtTextInput "Enter an ending IP for network range")
        if [[ $? -gt 0 ]] || [[ $txtIPEnd == "" ]]; then
            menuNetworks
            exit
        fi
        txtIPCIDR=$(wtTextInput "Enter the CIDR mask for your network e.g. x.x.x.0/24")
        if [[ $? -gt 0 ]] || [[ $txtIPCIDR == "" ]]; then
            menuNetworks
            exit
        fi
        jsonPayload=$(jq -n --arg netName "$txtNetName" --arg ipRangeStart "$txtIPStart" --arg ipRangeEnd "$txtIPEnd" --arg ipCIDR "$txtIPCIDR" '{"name":$netName,"ipAssignmentPools":[{"ipRangeStart":$ipRangeStart,"ipRangeEnd":$ipRangeEnd}], "routes":[{"target":$ipCIDR,"via":null}], "v4AssignMode":"zt","private":true}')
        wtConfirm "Are these settings correct? $jsonPayload"
        if [[ $? ]]; then
            jsonNewNetwork=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NODEADDRESS}______" -H "X-ZT1-AUTH: ${TOKEN}" -d "$jsonPayload")
            wtMsgBox "$jsonNewNetwork"
            menuNetworks
            exit
        else
            wtConfirm "Would you like to start again?"
            if [[ $? ]]; then
                networkCreate
            else
                menuNetworks
            fi
        fi
    fi
    exit
}

function networkDelete() {
    NWID=$1
    whiptail --yesno "Are you sure you want to delete network $NWID?" $WTH $WTW
    if [[ $? -eq 0 ]]; then
        jsonNetworkDelete=$(curl -s -X DELETE "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}" -H "X-ZT1-AUTH: ${TOKEN}")
        wtMsgBox "Network $NWID deleted"
    fi
    networkList
    exit
}

function networkInfo() {
    NWID=$1
    jsonNetworkInfo=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" )
    formatted=$(echo $jsonNetworkInfo | jq)
    wtInfoMsgBox "$formatted"
    menuNetwork $NWID
}

function networkMembers() {
    NWID=$1
    jsonNetworkMembers=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member" -H "X-ZT1-AUTH: ${TOKEN}")
    arrMembers=($(echo $jsonNetworkMembers | jq -r 'keys[]'))
    if [[ ${#arrMembers} -eq 0 ]]; then
        wtMsgBox "This network has no members, please join some devices to this network"
        menuNetwork $NWID
        exit
    fi
    miMembers=()
    MEMSTATUS="-"
    for i in ${arrMembers[@]}; do
        miMembers+=("$i")

        jsonNetworkMemberStatus=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${i}" -H "X-ZT1-AUTH: ${TOKEN}")
        memAuthStatus=$(echo $jsonNetworkMemberStatus | jq .authorized)
        memIPAddress=$(echo $jsonNetworkMemberStatus | jq -r .ipAssignments[0])
        case $memAuthStatus in
            "true")
                MEMSTATUS="Authorised [$memIPAddress]"
            ;;
            "false")
                MEMSTATUS="Not-Authorised"
            ;;
        esac
        miMembers+=(" ($MEMSTATUS) ")
    done
    menuMembers=$(whiptail --title "$TITLE" --menu "Zerotier Network $NWID Member List" $WTH $WTW 8 --cancel-button Back --ok-button Select "${miMembers[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuNetwork $NWID
    fi
    memberMenu $NWID $menuMembers
}

function memberInfo() {
    NWID=$1
    MEMID=$2
    jsonMemberInfo=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MEMID}" -H "X-ZT1-AUTH: ${TOKEN}" )
    formatted=$(echo $jsonMemberInfo | jq)
    wtInfoMsgBox "$formatted"
    memberMenu $NWID $MEMID
}

function memberMenuConfig() {
    NWID=$1
    MEMID=$2
    txtNewMemberIP=$(whiptail --title "$TITLE" --inputbox "New IP Address" $WTH $WTW 3>&1 1>&2 2>&3)
    if [[ $? == 1 ]]; then
        memberMenu $NWID $MEMID
    fi
    jsonIPUpdate=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MEMID}" -H "X-ZT1-AUTH: ${TOKEN}" -d '{"ipAssignments": ["'$txtNewMemberIP'"]}')
    memberMenu $NWID $MEMID
}

function memberAuth() {
    NWID=$1
    MEMID=$2
    jsonMemberAuth=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MEMID}" -H "X-ZT1-AUTH: ${TOKEN}" -d '{"authorized": true}')
    MEMSTATUS="Authorised"
    memberMenu $NWID $MEMID
}

function memberDeauth() {
    NWID=$1
    MEMID=$2
    jsonMemberDeauth=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MEMID}" -H "X-ZT1-AUTH: ${TOKEN}" -d '{"authorized": false}')
    MEMSTATUS="Deauthorised"
    memberMenu $NWID $MEMID
}

function memberDelete() {
    NWID=$1
    MID=$2

    MEMSTATUS=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MID}" -H "X-ZT1-AUTH: ${TOKEN}" | jq -r .authorized)
    if [[ $MEMSTATUS == "true" ]]; then
        wtMsgBox "Member still authorised. Please de-authorise member before deleting"
        memberMenu $NWID $MID
        exit
    fi

    wtConfirm "Are you sure you want to delete member $MID?"
    if [[ $? ]]; then
        jsonDeleteMember=$(curl -sw "%{http_code}" -X DELETE "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MID}" -H "X-ZT1-AUTH: ${TOKEN}")
        resp=$(curlGetHTTPCode $jsonDeleteMember)
        if [[ $resp == "200" ]]; then
            wtMsgBox "Successfully deleted $MID"
            #wtMsgBox "$jsonDeleteMember"
            networkMembers $NWID
            exit
        else
            wtMsgBox "Unable to delete member $MID"
            memberMenu $NWID $MID
        fi
    fi
    memberMenu $NWID $MID
}

function memberMenu() {
    NWID=$1
    MID=$2
    MEMSTATUS=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/member/${MID}" -H "X-ZT1-AUTH: ${TOKEN}" | jq .authorized)
    menuItems=("Member Info" "" "Set Member IP" "" "Auth Member" "" "Deauth Member" "" "Delete Member" "")
    menuText=("Zerotier Network $NWID \nMember Menu - $MID \nMember Authorised - $MEMSTATUS")
    menuMember=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 8 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        networkMembers $NWID
    fi
    case $menuMember in
        "Member Info")
            memberInfo $NWID $MID
        ;;
        "Set Member IP")
            memberMenuConfig $NWID $MID
        ;;
        "Auth Member")
            memberAuth $NWID $MID
        ;;
        "Deauth Member")
            memberDeauth $NWID $MID
        ;;
        "Delete Member")
            memberDelete $NWID $MID
        ;;
        *)
            echo "Default - $menuMember"
        ;;
    esac
}

function networkList() {
    jsonNetworkList=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/" -H "X-ZT1-AUTH: ${TOKEN}" )
    Networks=($(echo $jsonNetworkList | jq -r '.[]'))
    if [[ ${#Networks} -eq 0 ]]; then
        wtMsgBox "No networks found. Please create a network"
        menuNetworks
    fi
    miNetworks=()
    miNetworkItem=""
    for i in ${Networks[@]}; do
        miNetworks+=("$i")
        jsonNetworkName=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/{$i}" -H "X-ZT1-AUTH: ${TOKEN}" | jq -r .name)
        if [[ $jsonNetworkName ]]; then
            miNetworkName="$jsonNetworkName"
        else
            miNetworkName="-"
        fi
        miNetworks+=("  ($miNetworkName) ")
    done

    menuNetworkList=$(whiptail --title "$TITLE" --menu "ZeroTier Network List\nChoose a Network Below:" $WTH $WTW 8 --cancel-button Back --ok-button Select "${miNetworks[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuNetworks
        exit
    fi

    if [[ ${#menuNetworkList} -ne 16  ]]; then
        wtMsgBox "Error selecting network. Please try again"
        menuNetworks
    else
        menuNetwork $menuNetworkList
    fi
}

function networkConfigRoutesShow() {
    NWID=$1
    jsonNetworkInfo=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" )
    arrCurrentRoutes=$(echo $jsonNetworkInfo | jq -r .routes[])
    if [[ ${#arrCurrentRoutes} -eq 0 ]]; then
        wtMsgBox "No routes yet. Please create a route for this network"
        networkConfigRoutes $NWID
    fi
    wtInfoMsgBox "$arrCurrentRoutes"
    networkConfigRoutes $NWID
}

function networkConfigRouteAdd() {
    NWID=$1
    txtNewRoute=$(whiptail --title "$TITLE" --inputbox "Enter Destination Network and CIDR mask, or leave blank to cancel" $WTH $WTW 3>&1 1>&2 2>&3)
    if [[ $txtNewRoute ]]; then
        txtNewRouteGW=$(whiptail --title "$TITLE" --inputbox "Network: $txtNewRoute\nEnter Gateway for Network" $WTH $WTW 3>&1 1>&2 2>&3)
        if [[ $txtNewRouteGW ]]; then
            confirm=$(whiptail --title "$TITLE" --yesno "Network: $txtNewRoute\nGateway: $txtNewRouteGW\nAre These Details Correct?" $WTH $WTW 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                jsonCurrentRoute=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq -c .routes)
                jsonNewRoute=$(jq -c -n --arg net "$txtNewRoute" --arg gw "$txtNewRouteGW" '[{target:$net,via:$gw}]')
                jsonPayload=$(echo $jsonCurrentRoute $jsonNewRoute | jq -s add -c | jq '{"routes": .}')
                jsonAddNewRoute=$(curl -s -d "$jsonPayload" -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq .routes)
                wtInfoMsgBox "Added New Route\nCurrent Routes: $jsonAddNewRoute"
                networkConfigRoutes $NWID
            else
                wtMsgBox "Adding Route Cancelled"
                networkConfigRoutes $NWID
            fi
        else
            wtMsgBox "No Gateway Entered, No Route was added"
            networkConfigRoutes $NWID
        fi
    else
        wtMsgBox "No IP Entered, No Route was added"
        networkConfigRoutes $NWID
    fi
}

function networkConfigRouteDelete() {
    NWID=$1
    jsonData=($(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq -c .routes[]))
    miRoutes=()
    if [[ ${#jsonData} -lt 3 ]]; then
        wtMsgBox "No Routes to delete"
        networkConfigRoutes $NWID
    fi
    for i in "${jsonData[@]}"; do
        miRoutes+=("$i" "  (-) ")
    done
    menuRouteDelete=$(whiptail --title "$TITLE" --menu "Zerotier Network Configuration $idNetwork\nDelete Route" $WTH $WTW 4 --cancel-button Back --ok-button Delete "${miRoutes[@]}"  3>&1 1>&2 2>&3)
    if [[ $? -gt 0 ]]; then
        networkConfigRoutes $NWID
        exit
    fi
    jsonExisting=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq -c .routes)
    jsonTarget=$(echo $menuRouteDelete | jq -c .target)
    jsonIndex=$(echo $jsonExisting | jq 'map(.target == '$jsonTarget') | index(true)')
    jsonPayload=$(echo $jsonExisting | jq 'del(.['$jsonIndex'])' | jq -c '{"routes": .}')
    jsonDeleteRoute=$(curl -s -d "$jsonPayload" -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq .routes)
    wtInfoMsgBox "Deleted Route\nCurrent Routes: $jsonDeleteRoute"
    networkConfigRoutes $NWID
}

function networkConfigRoutes() {
    NWID=$1
    menuItems=("Show Current Routes" "" "Add New Route" "" "Delete Route" "")
    menuSelect=$(whiptail --title "$TITLE" --menu "Zerotier Network Configuration $idNetwork \nRouting" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        networkConfig $NWID
        exit
    fi

    case "$menuSelect" in
        "Show Current Routes")
            networkConfigRoutesShow $NWID
        ;;
        "Add New Route")
            networkConfigRouteAdd $NWID
        ;;
        "Delete Route")
            networkConfigRouteDelete $NWID
        ;;
    esac
    exit
}

function networkConfigDescription() {
    NWID=$1
    jsonData=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -H "X-ZT1-AUTH: ${TOKEN}" | jq .name)
    if [[ jsonData == "" ]]; then
       txtDesc="No Description Set"
    else
       txtDesc=$jsonData
    fi

    txtNewDesc=$(whiptail --title "$TITLE" --inputbox "Current Description: $txtDesc \nPlease enter a new description or leave blank to cancel." $WTH $WTW 3>&1 1>&2 2>&3)
    if [[ ! $txtNewDesc == "" ]]; then
        jsonNewDesc=$(jq -n --arg txtNewDesc "$txtNewDesc" '{ name: $txtNewDesc }')
        jsonData=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -d "$jsonNewDesc" -H "X-ZT1-AUTH: ${TOKEN}" | jq .name)
        wtMsgBox "Description was updated to $jsonData"
        networkConfig $NWID
    else
        wtMsgBox "Description was not updated"
        networkConfig $NWID
    fi
}

function networkConfigIPRange() {
    NWID=$1
    txtIPStart=$(whiptail --title "$TITLE" --inputbox "Enter starting IP address for address range" $WTH $WTW 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]] || [[ ! $txtIPStart ]]; then
        networkConfig $NWID
    fi
    txtIPEnd=$(whiptail --title "$TITLE" --inputbox "Enter ending IP address for address range" $WTH $WTW  3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]] || [[ ! $txtIPEnd ]]; then
        networkConfig $NWID
    fi
    txtIPCIDR=$(whiptail --title "$TITLE" --inputbox "Enter range CIDR subnet e.g. x.x.x.0/24" $WTH $WTW  3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]] | [[ ! $txtIPCIDR ]]; then
        networkConfig $NWID
    fi
    if [[ $txtIPStart ]] && [[ $txtIPEnd ]] && [[ $txtIPCIDR ]]; then
        jsonPayload=$(jq -n --arg IPStart "$txtIPStart" --arg IPEnd "$txtIPEnd" --arg CIDR "$txtIPCIDR" '{ipAssignmentPools:[{ipRangeStart:$IPStart,ipRangeEnd:$IPEnd}],routes:[{target:$CIDR,via:null}],v4AssignMode:"zt"}')
        jsonNewIPRange=$(curl -s -X POST "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${NWID}/" -d "$jsonPayload" -H "X-ZT1-AUTH: ${TOKEN}")
        jsonOutput=$(echo "$jsonNewIPRange" | jq '("IP Address Range",.ipAssignmentPools[],"routes", .routes[])')
        wtMsgBox "New IP Range set:\n$jsonOutput"
        networkConfig $NWID
    else
        wtMsgBox "Invalid Data for IP.\n$txtIPStart\n$txtIPEnd"
        networkConfig $NWID
    fi
}

function networkConfig() {
    idNetwork=$1
    jsonNetworkInfo=$(curl -s "http://$CONTROLLERIP:$CONTROLLERPORT/controller/network/${idNetwork}/" -H "X-ZT1-AUTH: ${TOKEN}" )
    txtIPStart=$(echo $jsonNetworkInfo | jq -r .ipAssignmentPools[0].ipRangeStart)
    txtIPEnd=$(echo $jsonNetworkInfo | jq -r .ipAssignmentPools[0].ipRangeEnd)
    txtNetName=$(echo $jsonNetworkInfo | jq -r .name)
    menuText="ZeroTier Network Configuration $idNetwork\nNetwork Name: $txtNetName\nIP Range : $txtIPStart - $txtIPEnd\n"
    menuItems=("Manage Routes" "" "Modify Network Name" "" "Modify IP Range" "")
    menuSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        menuNetwork $idNetwork
        exit
    fi
    case $menuSelect in
        "Manage Flow Rules")
            whiptail --title "$TITLE" --msgbox  "TODO : Manage Flow Rules" $WTH $WTW
            networkConfig $idNetwork
        ;;
        "Manage Routes")
            networkConfigRoutes $idNetwork
        ;;
        "Modify Network Name")
            networkConfigDescription $idNetwork
        ;;
        "Modify IP Range")
            networkConfigIPRange $idNetwork
        ;;
    esac

    exit
}

function menuNetwork() {
    idNetwork=$1
    menuItems=("Network Info" "" "Configure Network" "" "List Network Members" "" "Delete Network" "")
    menuText="ZeroTier Network $idNetwork"
    menuSelect=$(whiptail --title "$TITLE" --menu "$menuText" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    if [[ $? -eq 1 ]]; then
        networkList
        exit
    fi
    case $menuSelect in
        "Network Info")
            networkInfo $idNetwork
        ;;
        "Configure Network")
            networkConfig $idNetwork
        ;;
        "List Network Members")
            networkMembers $idNetwork
        ;;
        "Delete Network")
            networkDelete $idNetwork
        ;;
    esac
    exit
}

function menuNetworks() {
    menuItems=("Create Network" "" "List Networks" "")
    menuSelect=$(whiptail --title "$TITLE" --menu "ZeroTier Networking Menu" $WTH $WTW 4 --cancel-button Back --ok-button Select "${menuItems[@]}" 3>&1 1>&2 2>&3)
    RET=$?
    if [[ $RET -eq 1 ]]; then
        menuController
    fi
    case $menuSelect in
        "Create Network")
            networkCreate
        ;;
        "List Networks")
            networkList
        ;;
    esac
}

function menuClients() {
    echo "Clients Menu"
}

getAuth
menuMain
