#!/bin/bash

# GENERAL FUNCTIONS

function help_message(){

    # If has message, prints as error
    ERR_MESSAGE=$1
    EXIT_COD=0

    if ! [ -z "$ERR_MESSAGE" ];then
        echo
        echo "ERROR: $ERR_MESSAGE"
        echo
        EXIT_COD=1
    fi

    # Help message defaults
    cat <<EOF

!!WARNING!! ONLY TESTED IN ORACLE 8 !!WARNING!!

This scrit is only used to setup Ranger.
OPTIONS:
--build                                     [1st] Run the build ranger proccess.
--install [/path/to/ranger/builded]         [2nd] Install Ranger with the builded Ranger path.
--reinstall [/path/to/ranger/builded]       [if needed] Reinstall Ranger with the builded Ranger path.
--uninstall                                 [if needed] Uninstall Ranger if '--hadoop-folder' not passed
                                            script will try remove Ranger in /usr/ranger.
--hadoop-folder [/path/to/hadoop]           [optional] Install Ranger in [/path/to/hadoop] folder
                                            if not use --hadoop-folder the path default is /usr/ranger

--help                                      This help message.

DOC:
The '--setup [/path/to/ranger/builded]' will try search target subdirectory
In the --hadoop-folder [/path/to/hadoop] needs path where hadoop was intalled
Exemple: the bigtop installs hadoop in /var/lib/ambari-server/resources/common-services/

EOF

    # exits script
    exit $EXIT_COD
}

# LOG INITIALIZE
LOG_PATH="${PWD}/logs"
if ! [ -d $LOG_PATH ];then mkdir -p $LOG_PATH;fi
LOG_FILE_NAME="ranger_setup"
LOG_FILE="${LOG_PATH}/${LOG_FILE_NAME}.log"
LOG_QTY=$(find "$LOG_PATH" -name "*.log" -type f | wc -l)
# LOG ROTATE
if [ $LOG_QTY -gt 0 ];then
    for i in $(seq $LOG_QTY -1 1);do
        if [ $i -gt 10 ];then rm -f "${LOG_PATH}/${LOG_FILE_NAME}-${i}.log";continue;fi
        if [ $i -eq 1 ];then  mv -f "${LOG_FILE}" "${LOG_PATH}/${LOG_FILE_NAME}-${i}.log" &>/dev/null;continue;fi
        FILE_IDX=$(( $i - 1 ))
        mv -f "${LOG_PATH}/${LOG_FILE_NAME}-${FILE_IDX}.log" "${LOG_PATH}/${LOG_FILE_NAME}-${i}.log" &>/dev/null
    done
fi
touch "$LOG_FILE" &>/dev/null
function logger(){
    # usage logger "${FUNCNAME[0]}" $LOGTYPE "Log message"

    # PARAMETERS
    FUNC_NAME=$1 # Name of function
    LOG_TYPE=$2 # INFO WARNING ERROR
    MESSAGE=$3 # Some log message

    # VARIABLES
    CURR_TIME=$(date +'%Y-%m-%d %H:%M:%S')

    # Creates log message
    LOG_MESSAGE="${CURR_TIME} - ${FUNC_NAME} - ${LOG_TYPE} - ${MESSAGE}"

    # Commit log
    echo "${LOG_MESSAGE}" | tee -a $LOG_FILE
}


# OPERATING SYSTEM TOOLS

function install_package(){
    # usage: install_package "package1 package2 package3..."
    logger "${FUNCNAME[0]}" "INFO" "Installing packages proccess"

    # PARAMETER
    PACKAGES_NAME=$1

    # Used to return after execution
    RETURN_COD=0

    # LOOP THROUGH PACKAGES NAME
    for PACKAGE in $(echo ${PACKAGES_NAME});do
        yum list installed "${PACKAGE}*" &>/dev/null
        if [ $? -eq 0 ];then
            logger "${FUNCNAME[0]}" "INFO" "${PACKAGE} already installed"
            continue;
        fi
        logger "${FUNCNAME[0]}" "INFO" "Installing package: ${PACKAGE}"

        # Install command in silent mode
        yum install -y $PACKAGE &>/dev/null
        CHK_COD=$?

        # Checking if installation worked
        if [ $CHK_COD -gt 0 ];then
            logger "${FUNCNAME[0]}" "ERROR" "Error to install package: ${PACKAGE}"
            logger "${FUNCNAME[0]}" "ERROR" "Run yum install $PACKAGE and try check manually"
            RETURN_COD=1
            continue;
        fi

        logger "${FUNCNAME[0]}" "INFO" "Package installed successfully: ${PACKAGE}"
    done

    # RETURN RESULT
    logger "${FUNCNAME[0]}" "INFO" "Installing packages proccess DONE"
    return $RETURN_COD
}

function create_folder(){
    # usage: create_folder FOLDER_PATH
    FOLDER_PATH=$1
    logger "${FUNCNAME[0]}" "INFO" "Creat folder: ${FOLDER_PATH}"
    mkdir -p "${FOLDER_PATH}" &>/dev/null
    CHK_COD=$?

    if [ $CHK_COD -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to creat folder: ${FOLDER_PATH}"
        return 1
    fi
    return 0
}

# RANGER BUILD/SETUP

function install_maven(){
    # usage: install_maven INSTALL_PATH
    logger "${FUNCNAME[0]}" "INFO" "Installing maven"

    # PARAMETERS
    INSTALL_PATH=$1

    # Checking if already installed
    mvn --version &>/dev/null
    CHK_COD=$?
    if [ $CHK_COD -eq 0 ];then
        logger "${FUNCNAME[0]}" "INFO" "Maven already installed"
        return 0
    fi
    # if install_package "maven";then
    #     logger "${FUNCNAME[0]}" "INFO" "Installing maven DONE"
    #     return 0
    # fi
    logger "${FUNCNAME[0]}" "WARNING" "Maven not installed by package manager. Trying install from binary."

    # Download Maven
    logger "${FUNCNAME[0]}" "INFO" "Installing maven from binary"
    logger "${FUNCNAME[0]}" "INFO" "Downloading Maven binary..."
    NOT_EXIST=$(find "${INSTALL_PATH}/" -name "apache-maven-*.tar.gz" -type f)
    if [ -z "$NOT_EXIST" ];then
        wget -P $INSTALL_PATH https://dlcdn.apache.org/maven/maven-3/3.9.4/binaries/apache-maven-3.9.4-bin.tar.gz &>/dev/null
        logger "${FUNCNAME[0]}" "INFO" "Download DONE"
    fi

    # Unpack Maven
    logger "${FUNCNAME[0]}" "INFO" "Unpack Maven binary in /usr/local/"
    MAVEN_VERSION=$(ls -A $INSTALL_PATH | grep apache-maven- | awk -F '-' '{print $3}' | head -1)
    tar -zxf "${INSTALL_PATH}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C /usr/local/
    CHK_COD=$?

    if [ $CHK_COD -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to unpack Maven binary in /usr/local/"
        return 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Unpack Maven binary in /usr/local/ DONE"

    # Setup maven
    logger "${FUNCNAME[0]}" "INFO" "Setup Maven"

    # Creating script on /etc/profile.d
    cat <<EOF > /etc/profile.d/maven.sh
export M2_VERSION=$(ls -A /usr/local/ | grep apache-maven- | grep -v .gz | awk -F '-' '{print $3}')
export M2_HOME=/usr/local/apache-maven-\$M2_VERSION
export M2=\$M2_HOME/bin

export PATH=\${M2}:\$PATH
EOF
    chmod +x /etc/profile.d/maven.sh
    if ! echo $PATH | grep -q "maven-${MAVEN_VERSION}";then
        source /etc/profile.d/maven.sh
    fi

    # Testing maven
    logger "${FUNCNAME[0]}" "INFO" "Check maven installation"
    mvn --version &>/dev/null
    CHK_COD=$?
    if [ $CHK_COD -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to install Maven"
        return 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Installing maven DONE"
    return 0
}

function build_ranger(){
    # usage: build_ranger INSTALL_PATH
    logger "${FUNCNAME[0]}" "INFO" "Build Ranger proccess"

    # PARAMETERS
    INSTALL_PATH=$1

    # VARIABLES
    RANGER_BUILD_PATH="${INSTALL_PATH}/ranger"
    REPOSITORY="https://gitbox.apache.org/repos/asf/ranger.git"

    # If has path ranger empty delete
    if ! ls -l $RANGER_BUILD_PATH 2>/dev/null | grep -q pom.xml;then
        logger "${FUNCNAME[0]}" "WARNING" "Found ranger folder without build file"
        logger "${FUNCNAME[0]}" "WARNING" "Removing ${RANGER_BUILD_PATH} folder"
        rm -rf "${RANGER_BUILD_PATH}"
    fi

    logger "${FUNCNAME[0]}" "INFO" "Getting sources from git"
    if ! [ -d "$RANGER_BUILD_PATH" ];then
        # get last tag
        GIT_TAG=$(git ls-remote --tags --exit-code --refs "$REPOSITORY" | sed -E 's/^[[:xdigit:]]+[[:space:]]+refs\/tags\/(.+)/\1/g' | tail -n1)

        # clone repository
        git clone --branch "$GIT_TAG" --depth 1 "$REPOSITORY" "${RANGER_BUILD_PATH}"
    fi
    cd $RANGER_BUILD_PATH
    logger "${FUNCNAME[0]}" "INFO" "Running maven command to compile Ranger"
    mvn -Pall clean 
    mvn -Pall -DskipTests=false clean compile package
    CHK_COD=$?
    cd $PWD
    if [ $CHK_COD -gt 0 ];then
        return 1
    fi

    return 0
}

# SETUP RANGER

function setup_ranger_folders(){
    # usage: setup_ranger_folders
    logger "${FUNCNAME[0]}" "INFO" "Creating folders structure"
    
    # Checking if folders already exist if not create it
    if ! [ -d "${HADOOP_FOLDER}" ];then 
        if ! create_folder "${HADOOP_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${SOLR_FOLDER}" ];then 
        if ! create_folder "${SOLR_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${SOLR_LOG_FOLDER}" ];then 
        if ! create_folder "${SOLR_LOG_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_ADMIN_FOLDER}" ];then 
        if ! create_folder "${RANGER_ADMIN_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_ADMIN_LOG_FOLDER}" ];then 
        if ! create_folder "${RANGER_ADMIN_LOG_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_USERSYNC_FOLDER}" ];then 
        if ! create_folder "${RANGER_USERSYNC_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_USERSYNC_LOG_FOLDER}" ];then 
        if ! create_folder "${RANGER_USERSYNC_LOG_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_ADMIN_CONF_FOLDER}" ];then 
        if ! create_folder "${RANGER_ADMIN_CONF_FOLDER}";then return 1;fi
    fi

    if ! [ -d "${RANGER_USERSYNC_CONF_FOLDER}" ];then 
        if ! create_folder "${RANGER_USERSYNC_CONF_FOLDER}";then return 1;fi
    fi

    return 0
}

function clean_user_db(){
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -h"$MYSQL_HOST" <<MYSQLSCRIPT &>/dev/null
DROP USER '$MYSQL_RANGER_USERNAME'@'$(hostname -i)';
DROP USER '$MYSQL_RANGER_USERNAME'@'localhost';
DROP USER '$MYSQL_RANGER_USERNAME'@'$(hostname)';
FLUSH PRIVILEGES;
MYSQLSCRIPT
}

function setup_solr(){
    # usage: setup_solr "${RANGER_BUILDED_PATH}"
    logger "${FUNCNAME[0]}" "INFO" "Setup solr"
    RANGER_BUILDED_PATH=$1

    # setup folder and files
    SOLR_SETUP_FOLDER="${RANGER_BUILDED_PATH}/security-admin/contrib/solr_for_audit_setup"
    SOLR_SETUP_PROPERTIES_FILE="${SOLR_SETUP_FOLDER}/install.properties"
    SOLR_SETUP_SCRIPT="${SOLR_SETUP_FOLDER}/setup.sh"

    # install folder and files
    SOLR_SCRIPT_START="${SOLR_FOLDER}/ranger_audit_server/scripts/start_solr.sh"
    SOLR_SCRIPT_STOP="${SOLR_FOLDER}/ranger_audit_server/scripts/"

    logger "${FUNCNAME[0]}" "INFO" "Checking Ranger builded folder"
    # Check if solr folder exist
    if [ ! -f $SOLR_SETUP_PROPERTIES_FILE ] || [ ! -f $SOLR_SETUP_SCRIPT ];then
        logger "${FUNCNAME[0]}" "ERROR" "Something wrong with Ranger builded in ${RANGER_BUILDED_PATH}"
        logger "${FUNCNAME[0]}" "ERROR" "Files install.properties or setup.sh in ${SOLR_SETUP_FOLDER} not found"
        return 1
    fi

    if [ -f "$SOLR_SCRIPT_START" ];then
        logger "${FUNCNAME[0]}" "INFO" "Solr already installed"
        return 0
    fi

    logger "${FUNCNAME[0]}" "INFO" "Configuring solr installation"

    # Change setup properties
    SOLR_BIN_URL="${SOLR_URL}/solr-${SOLR_VERSION}.tgz"

    SOLR_LOG_FOLDER=/var/log/hadoop/solr/ranger_audits

    cp "${SOLR_SETUP_PROPERTIES_FILE}" "${SOLR_SETUP_PROPERTIES_FILE}.bkp" &>/dev/null

    logger "${FUNCNAME[0]}" "INFO" "SOLR_INSTALL=true"
    sed -i "s|^SOLR_INSTALL=.*|SOLR_INSTALL=true|g" "$SOLR_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "SOLR_DOWNLOAD_URL=$SOLR_BIN_URL"
    sed -i "s|^SOLR_DOWNLOAD_URL=.*|SOLR_DOWNLOAD_URL=$SOLR_BIN_URL|g" "$SOLR_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "SOLR_LOG_FOLDER=$SOLR_LOG_FOLDER"
    sed -i "s|^SOLR_LOG_FOLDER=.*|SOLR_LOG_FOLDER=$SOLR_LOG_FOLDER|g" "$SOLR_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "Changing solr installation path from /opt/solr to ${SOLR_FOLDER}"
    sed -i "s|\/opt\/solr|${SOLR_FOLDER}|g" "$SOLR_SETUP_PROPERTIES_FILE"

    # setup solr
    logger "${FUNCNAME[0]}" "INFO" "Running setup solr"
    chmod +x "$SOLR_SETUP_SCRIPT"
    cd "$SOLR_SETUP_FOLDER"
    sh ./setup.sh
    CHK_COD=$?

    if [ $CHK_COD -gt 0 ];then return 1;fi
    cd $PWD

    logger "${FUNCNAME[0]}" "INFO" "Solr installed successfully"

    # Sarting solr
    SOLR_SCRIPT_START="${SOLR_FOLDER}/ranger_audit_server/scripts/start_solr.sh"
    SOLR_SCRIPT_STOP="${SOLR_FOLDER}/ranger_audit_server/scripts/stop_solr.sh"
    SOLR_SCRIPT_INIT="${SOLR_FOLDER}/ranger_audit_server/scripts/solr.in.sh"
    logger "${FUNCNAME[0]}" "INFO" "Creating alias to start and stop solr"

    if ! grep -q "$SOLR_SCRIPT_START" ~/.bashrc ;then
        cat <<EOF >> ~/.bashrc

# SOLR
alias solrstart='sh $SOLR_SCRIPT_START'
alias solrstop='sh $SOLR_SCRIPT_STOP'
EOF
    fi

    logger "${FUNCNAME[0]}" "INFO" "Starting solr"
    sh "${SOLR_SCRIPT_START}"
    
    nc -zv localhost 6083 &>/dev/null
    CHK_PORT_ACESS=$?
    if [ $CHK_PORT_ACESS -gt 0 ];then return 1;fi

    CHK_SOLR_PROCCESS=$(ps faux | grep -v grep | grep Dsolr | wc -l)
    if [ $CHK_SOLR_PROCCESS -eq 0 ];then return 1;fi

    rm -f "${SOLR_SETUP_PROPERTIES_FILE}"
    cp "${SOLR_SETUP_PROPERTIES_FILE}.bkp" "${SOLR_SETUP_PROPERTIES_FILE}" &>/dev/null
    
    return 0
}

function setup_ranger_admin(){
    # usage: setup_ranger_admin "${RANGER_BUILDED_PATH}"
    logger "${FUNCNAME[0]}" "INFO" "Setup Ranger admin"
    RANGER_BUILDED_PATH=$1

    # setup folder and files
    RANGER_ADMIN_BIN="${RANGER_BUILDED_PATH}/target/ranger-${RANGER_VERSION}-admin.tar.gz"

    # target files and folder
    RANGERADM_SETUP_PROPERTIES_FILE="${RANGER_ADMIN_FOLDER}/install.properties"
    RANGERADM_SETUP_SCRIPT="${RANGER_ADMIN_FOLDER}/setup.sh"

    logger "${FUNCNAME[0]}" "INFO" "Unpacking ${RANGER_ADMIN_BIN} file"
    cd "${RANGER_BUILDED_PATH}"
    tar -zxvf "$RANGER_ADMIN_BIN" -C "./target/" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to Unpacking ${RANGER_ADMIN_BIN} file"
        return 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Copying files to $RANGER_ADMIN_FOLDER"
    cd "${RANGER_BUILDED_PATH}/target/ranger-${RANGER_VERSION}-admin/" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to copy files to $RANGER_ADMIN_FOLDER"
        return 1
    fi
    cp -R * "$RANGER_ADMIN_FOLDER/" &>/dev/null

    if [ ! -f $RANGERADM_SETUP_PROPERTIES_FILE ] || [ ! -f $RANGERADM_SETUP_SCRIPT ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to copy files to $RANGER_ADMIN_FOLDER"
        return 1
    fi

    cp "${RANGERADM_SETUP_PROPERTIES_FILE}" "${RANGERADM_SETUP_PROPERTIES_FILE}.bkp" &>/dev/null

    # Config install.properties
    logger "${FUNCNAME[0]}" "INFO" "Configuring Ranger Admin install.properties"

    logger "${FUNCNAME[0]}" "INFO" "db_host=$MYSQL_HOST"
    sed -i "s|^db_host=.*|db_host=$MYSQL_HOST|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "db_root_user=$MYSQL_RANGER_USERNAME"
    sed -i "s|^db_root_user=.*|db_root_user=$MYSQL_RANGER_USERNAME|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "db_root_password=********"
    sed -i "s|^db_root_password=.*|db_root_password=$MYSQL_RANGER_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "db_name=ranger"
    sed -i "s|^db_name=.*|db_name=ranger|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "db_user=$MYSQL_RANGER_USERNAME"
    sed -i "s|^db_user=.*|db_user=$MYSQL_RANGER_USERNAME|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "db_password=********"
    sed -i "s|^db_password=.*|db_password=$MYSQL_RANGER_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "rangerAdmin_password=********"
    sed -i "s|^rangerAdmin_password=.*|rangerAdmin_password=$RANGERADM_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "rangerTagsync_password=********"
    sed -i "s|^rangerTagsync_password=.*|rangerTagsync_password=$RANGER_TAGSYNC_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "rangerUsersync_password=********"
    sed -i "s|^rangerUsersync_password=.*|rangerUsersync_password=$RANGER_USERSYNC_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "keyadmin_password=********"
    sed -i "s|^keyadmin_password=.*|keyadmin_password=$RANGER_KEYADMIN_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "audit_solr_urls=http://localhost:6083/solr/ranger_audits"
    sed -i "s|^audit_solr_urls=.*|audit_solr_urls=http:\/\/localhost:6083\/solr\/ranger_audits|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    #logger "${FUNCNAME[0]}" "INFO" "policymgr_supportedcomponents=hbase,hdfs,kafka,kms"
    #sed -i "s|^policymgr_supportedcomponents=.*|policymgr_supportedcomponents=hbase,hdfs,kafka,kms|g" "$RANGERADM_SETUP_PROPERTIES_FILE"
    logger "${FUNCNAME[0]}" "INFO" "authentication_method=$RANGER_AUTH_TYPE"
    sed -i "s|^authentication_method=.*|authentication_method=$RANGER_AUTH_TYPE|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    if [ $RANGER_AUTH_TYPE == 'UNIX' ];then

        logger "${FUNCNAME[0]}" "INFO" "remoteLoginEnabled=true"
        sed -i "s|^remoteLoginEnabled=.*|remoteLoginEnabled=true|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "authServiceHostName=localhost"
        sed -i "s|^authServiceHostName=.*|authServiceHostName=localhost|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "authServicePort=5151"
        sed -i "s|^authServicePort=.*|authServicePort=5151|g" "$RANGERADM_SETUP_PROPERTIES_FILE"
    fi

    if [ $RANGER_AUTH_TYPE == 'LDAP' ];then
        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_url=$XA_LDAP_URL"
        sed -i "s|^xa_ldap_url=.*|xa_ldap_url=$XA_LDAP_URL|g" "$RANGERADM_SETUP_PROPERTIES_FILE"
        
        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_userDNpattern=$XA_LDAP_USERDNPATTERN"
        sed -i "s|^xa_ldap_userDNpattern=.*|xa_ldap_userDNpattern=$XA_LDAP_USERDNPATTERN|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_groupSearchBase=$XA_LDAP_GROUPSEARCHBASE"
        sed -i "s|^xa_ldap_groupSearchBase=.*|xa_ldap_groupSearchBase=$XA_LDAP_GROUPSEARCHBASE|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_groupRoleAttribute=$XA_LDAP_GROUPROLEATTRIBUTE"
        sed -i "s|^xa_ldap_groupRoleAttribute=.*|xa_ldap_groupRoleAttribute=$XA_LDAP_GROUPROLEATTRIBUTE|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_base_dn=$XA_LDAP_BASEDN"
        sed -i "s|^xa_ldap_base_dn=.*|xa_ldap_base_dn=$XA_LDAP_BASEDN|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_bind_dn=$XA_LDAP_USERBIND"
        sed -i "s|^xa_ldap_bind_dn=.*|xa_ldap_bind_dn=$XA_LDAP_USERBIND|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_bind_password=********"
        sed -i "s|^xa_ldap_bind_password=.*|xa_ldap_bind_password=$XA_LDAP_USERBIND_PASSWORD|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_referral=$XA_LDAP_REFERRAL"
        sed -i "s|^xa_ldap_referral=.*|xa_ldap_referral=$XA_LDAP_REFERRAL|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "xa_ldap_userSearchFilter=$XA_LDAP_USERSEARCHFILTER"
        sed -i "s|^xa_ldap_userSearchFilter=.*|xa_ldap_userSearchFilter=$XA_LDAP_USERSEARCHFILTER|g" "$RANGERADM_SETUP_PROPERTIES_FILE"
    fi

    logger "${FUNCNAME[0]}" "INFO" "hadoop_conf=$HADOOP_CONF_PATH/"
    sed -i "s|^hadoop_conf=.*|hadoop_conf=$HADOOP_CONF_PATH/|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "RANGER_ADMIN_LOG_DIR=$HADOOP_CONF_PATH"
    sed -i "s|^RANGER_ADMIN_LOG_DIR=.*|RANGER_ADMIN_LOG_DIR=$RANGER_ADMIN_LOG_FOLDER|g" "$RANGERADM_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "Running setup Ranger admin"
    chmod +x "$RANGERADM_SETUP_SCRIPT"
    cd "$RANGER_ADMIN_FOLDER/" &>/dev/null
    sh ./setup.sh
    if [ $? -gt 0 ];then return 1;fi
    cd $PWD

    logger "${FUNCNAME[0]}" "INFO" "Give ranger user permissions and add to hadoop group"
    chown -R ranger: "$RANGER_ADMIN_FOLDER"
    CHK_COD1=$?
    chown -R ranger: "$RANGER_ADMIN_LOG_FOLDER"
    CHK_COD2=$?
    usermod -a -G hadoop ranger
    CHK_COD3=$?

    CHK_COD=$(( $CHK_COD1 + $CHK_COD2 + $CHK_COD3 ))
    if [ $CHK_COD -gt 0 ];then return 1;fi
    logger "${FUNCNAME[0]}" "INFO" "Ranger Admin installed successfully"

    logger "${FUNCNAME[0]}" "INFO" "Starting Ranger Admin"
    ranger-admin start
    nc -zv localhost 6080 &>/dev/null
    CHK_PORT_ACESS=$?
    if [ $CHK_PORT_ACESS -gt 0 ];then return 1;fi

    CHK_RANGERADMIN_PROCCESS=$(ps faux | grep -v grep | grep Dproc_rangeradmin | wc -l)
    if [ $CHK_RANGERADMIN_PROCCESS -eq 0 ];then return 1;fi

    rm -f "${RANGERADM_SETUP_PROPERTIES_FILE}"
    cp "${RANGERADM_SETUP_PROPERTIES_FILE}.bkp" "${RANGERADM_SETUP_PROPERTIES_FILE}" &>/dev/null

    ln -sf "${RANGER_ADMIN_FOLDER}/ews/webapp/WEB-INF/classes/conf" "${RANGER_ADMIN_CONF_FOLDER}/conf" &>/dev/null

    return 0
}

function setup_ranger_usersync(){
    # usage: setup_ranger_usersync "${RANGER_BUILDED_PATH}"
    logger "${FUNCNAME[0]}" "INFO" "Setup Ranger Usersync"
    RANGER_BUILDED_PATH=$1

    # setup folder and files
    RANGER_USERSYNC_BIN="${RANGER_BUILDED_PATH}/target/ranger-${RANGER_VERSION}-usersync.tar.gz"

    # target files and folder
    RANGERUSERSYNC_SETUP_PROPERTIES_FILE="${RANGER_USERSYNC_FOLDER}/install.properties"
    RANGERUSERSYNC_SETUP_SCRIPT="${RANGER_USERSYNC_FOLDER}/setup.sh"

    logger "${FUNCNAME[0]}" "INFO" "Unpacking ${RANGER_USERSYNC_BIN} file"
    cd "${RANGER_BUILDED_PATH}"
    tar -zxvf "$RANGER_USERSYNC_BIN" -C "./target/" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to Unpacking ${RANGER_USERSYNC_BIN} file"
        return 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Copying files to $RANGER_USERSYNC_FOLDER"
    cd "${RANGER_BUILDED_PATH}/target/ranger-${RANGER_VERSION}-usersync/" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to copy files to $RANGER_USERSYNC_FOLDER"
        return 1
    fi
    cp -R * "$RANGER_USERSYNC_FOLDER/" &>/dev/null

    if [ ! -f $RANGERUSERSYNC_SETUP_PROPERTIES_FILE ] || [ ! -f $RANGERUSERSYNC_SETUP_SCRIPT ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to copy files to $RANGER_USERSYNC_FOLDER"
        return 1
    fi

    # Config install.properties

    cp "${RANGERUSERSYNC_SETUP_PROPERTIES_FILE}" "${RANGERUSERSYNC_SETUP_PROPERTIES_FILE}.bkp" &>/dev/null

    logger "${FUNCNAME[0]}" "INFO" "Configuring Ranger Usersync install.properties"

    logger "${FUNCNAME[0]}" "INFO" "POLICY_MGR_URL = http:\/\/localhost:6080"
    sed -i "s|^POLICY_MGR_URL =.*|POLICY_MGR_URL = http:\/\/localhost:6080|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "rangerUsersync_password=********"
    sed -i "s|^rangerUsersync_password=.*|rangerUsersync_password=$RANGER_USERSYNC_PASSWORD|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "hadoop_conf=$HADOOP_CONF_PATH/"
    sed -i "s|^hadoop_conf=.*|hadoop_conf=$HADOOP_CONF_PATH/|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "logdir=$RANGER_USERSYNC_LOG_FOLDER/"
    sed -i "s|^logdir=.*|logdir=$RANGER_USERSYNC_LOG_FOLDER/|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    logger "${FUNCNAME[0]}" "INFO" "Changing Ranger Usersync installation path from /etc/ranger to ${RANGER_USERSYNC_FOLDER}"
    sed -i "s|\/etc\/ranger|${RANGER_USERSYNC_FOLDER}|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    if [ $RANGER_AUTH_TYPE == 'UNIX' ];then

        logger "${FUNCNAME[0]}" "INFO" "SYNC_SOURCE = unix"
        sed -i "s|^SYNC_SOURCE =.*|SYNC_SOURCE = unix|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_INTERVAL = 5"
        sed -i "s|^SYNC_INTERVAL =.*|SYNC_INTERVAL = 5|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"
    fi

    if [ $RANGER_AUTH_TYPE == 'LDAP' ];then
        logger "${FUNCNAME[0]}" "INFO" "SYNC_GROUP_NAME_ATTRIBUTE=$XA_LDAP_GROUPROLEATTRIBUTE"
        sed -i "s|^SYNC_GROUP_NAME_ATTRIBUTE=.*|SYNC_GROUP_NAME_ATTRIBUTE=$XA_LDAP_GROUPROLEATTRIBUTE|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_GROUP_SEARCH_BASE=$XA_LDAP_GROUPSEARCHBASE"
        sed -i "s|^SYNC_GROUP_SEARCH_BASE=.*|SYNC_GROUP_SEARCH_BASE=$XA_LDAP_GROUPSEARCHBASE|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        #logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_USER_GROUP_NAME_ATTRIBUTE = memberof,ismemberof,member"
        #sed -i "s|^SYNC_LDAP_USER_GROUP_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_GROUP_NAME_ATTRIBUTE = memberof,ismemberof,member|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_USER_NAME_ATTRIBUTE = $XA_LDAP_GROUPROLEATTRIBUTE"
        sed -i "s|^SYNC_LDAP_USER_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_NAME_ATTRIBUTE = $XA_LDAP_GROUPROLEATTRIBUTE|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_USER_SEARCH_BASE = $LDAP_USER_SEARCH"
        sed -i "s|^SYNC_LDAP_USER_SEARCH_BASE =.*|SYNC_LDAP_USER_SEARCH_BASE = $LDAP_USER_SEARCH|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_URL = $XA_LDAP_URL"
        sed -i "s|^SYNC_LDAP_URL =.*|SYNC_LDAP_URL = $XA_LDAP_URL|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_BIND_DN = $XA_LDAP_USERBIND"
        sed -i "s|^SYNC_LDAP_BIND_DN =.*|SYNC_LDAP_BIND_DN = $XA_LDAP_USERBIND|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_LDAP_BIND_PASSWORD = ********"
        sed -i "s|^SYNC_LDAP_BIND_PASSWORD =.*|SYNC_LDAP_BIND_PASSWORD = $XA_LDAP_USERBIND_PASSWORD|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_SOURCE = ldap"
        sed -i "s|^SYNC_SOURCE =.*|SYNC_SOURCE = ldap|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

        logger "${FUNCNAME[0]}" "INFO" "SYNC_INTERVAL = 360"
        sed -i "s|^SYNC_INTERVAL =.*|SYNC_INTERVAL = 360|g" "$RANGERUSERSYNC_SETUP_PROPERTIES_FILE"

    fi

    logger "${FUNCNAME[0]}" "INFO" "Running setup Ranger Usersync"
    chmod +x "$RANGERUSERSYNC_SETUP_SCRIPT"
    cd "$RANGER_USERSYNC_FOLDER/" &>/dev/null
    sh ./setup.sh
    if [ $? -gt 0 ];then return 1;fi
    cd $PWD

    logger "${FUNCNAME[0]}" "INFO" "Give ranger user permissions and add to hadoop group"
    chown -R ranger: "$RANGER_USERSYNC_FOLDER"
    CHK_COD1=$?
    chown -R ranger: "$RANGER_USERSYNC_LOG_FOLDER"
    CHK_COD2=$?
    usermod -a -G hadoop ranger
    CHK_COD3=$?

    CHK_COD=$(( $CHK_COD1 + $CHK_COD2 + $CHK_COD3 ))
    if [ $CHK_COD -gt 0 ];then return 1;fi
    logger "${FUNCNAME[0]}" "INFO" "Ranger Usersync installed successfully"

    # Starting Usersync
    USERSYNC_SCRIPT_SERVICE="${RANGER_USERSYNC_FOLDER}/ranger-usersync-services.sh"
    logger "${FUNCNAME[0]}" "INFO" "Creating alias to start and stop Ranger Usersync"

    if ! grep -q "$USERSYNC_SCRIPT_SERVICE" ~/.bashrc ;then
        cat <<EOF >> ~/.bashrc

# RANGER USERSYNC
alias ranger-usersync='sh $USERSYNC_SCRIPT_SERVICE' # start or stop
EOF
    fi

    logger "${FUNCNAME[0]}" "INFO" "Starting Ranger Usersync"
    sh "${USERSYNC_SCRIPT_SERVICE}" start

    # Enable user sync in ranger-ugsync-site.xml
    logger "${FUNCNAME[0]}" "INFO" "ranger.usersync.enabled = true"

    RANGER_USERSYNC_CONF_XML="${RANGER_USERSYNC_FOLDER}/conf/ranger-ugsync-site.xml"
    if ! [ -f $RANGER_USERSYNC_CONF_XML ];then return 1;fi

    #LINE_NUMBER=$(grep -n -A1 '<name>ranger.usersync.enabled<\/name>' "$RANGER_USERSYNC_CONF_XML" | tail -1 | awk '{print $1}' | sed -e 's/://g' -e 's/-//g')
    #sed -i "${LINE_NUMBER}s/<value>.*/<value>true<\/value>/" "$RANGER_USERSYNC_CONF_XML"
    sed -i '/<name>ranger.usersync.enabled<\/name>/!b;n;c<value>true</value>' "$RANGER_USERSYNC_CONF_XML"
    

    logger "${FUNCNAME[0]}" "INFO" "Rebooting Ranger Usersync"
    sh "${USERSYNC_SCRIPT_SERVICE}" stop
    sh "${USERSYNC_SCRIPT_SERVICE}" start
    
    # Checking if services is UP
    MAX_RETRY_CHECK=3
    CHK_PORT_ACCESS=1
    for RETRY_CHECK in $(seq 1 $MAX_RETRY_CHECK);do
        logger "${FUNCNAME[0]}" "INFO" "Checking Ranger Usersync: $RETRY_CHECK"
        sleep 5

        # port check
        nc -zv localhost 5151 &>/dev/null
        if [ $? -eq 0 ];then 
            CHK_PORT_ACCESS=0
            break;
        fi
    done

    CHK_RANGERUSERSYNC_PROCCESS=$(ps faux | grep -v grep | grep Dproc_rangerusersync | wc -l)
    if [ $CHK_RANGERUSERSYNC_PROCCESS -eq 0 ];then return 1;fi

    if [ $CHK_PORT_ACCESS -gt 0 ];then return 1;fi

    rm -f "${RANGERUSERSYNC_SETUP_PROPERTIES_FILE}"
    cp "${RANGERUSERSYNC_SETUP_PROPERTIES_FILE}.bkp" "${RANGERUSERSYNC_SETUP_PROPERTIES_FILE}" &>/dev/null

    ln -sf "${RANGER_USERSYNC_FOLDER}/usersync/conf" "${RANGER_USERSYNC_CONF_FOLDER}/conf" &>/dev/null

    return 0
}


# MAIN

# Need be root
if [[ 'root' != $USER ]];then help_message "Run script as root user";fi

# Check empty parameters
if [ -z "$1" ];then help_message "Empty parameters";fi

# PARAMETER
P_BUILD=false
P_INSTALL=false
P_UNINSTALL=false
HADOOP_FOLDER="/usr/ranger"
CURRENT_FOLDER=$PWD
while [ $# -gt 0 ];do
    case $1 in
        '--build')
            P_BUILD=true
            shift
        ;;
        '--install')
            P_INSTALL=true
            if [ -z "$2" ];then help_message "--install needs [/path/to/ranger/builded].";fi
            if ! [ -d "$2" ];then help_message "Folder $2 not exist";fi
            RANGER_BUILDED_PATH=$(echo "$2" | sed 's/\/$//' )
            if [[ ${RANGER_BUILDED_PATH:0:1} == "." ]];then RANGER_BUILDED_PATH="${CURRENT_FOLDER}/${RANGER_BUILDED_PATH:1}";fi
            shift 2
        ;;
        '--reinstall')
            P_UNINSTALL=true
            P_INSTALL=true
            if [ -z "$2" ];then help_message "--reinstall needs [/path/to/ranger/builded].";fi
            if ! [ -d "$2" ];then help_message "Folder $2 not exist";fi
            RANGER_BUILDED_PATH=$(echo "$2" | sed 's/\/$//' )
            if [[ ${RANGER_BUILDED_PATH:0:1} == "." ]];then RANGER_BUILDED_PATH="${CURRENT_FOLDER}/${RANGER_BUILDED_PATH:1}";fi
            shift 2
        ;;
        '--uninstall')
            P_UNINSTALL=true
            shift
        ;;
        '--hadoop-folder')
            if [ -z "$2" ];then help_message "--hadoop-folder needs [/path/to/hadoop].";fi
            if ! [ -d "$2" ];then help_message "Folder $2 not exist";fi
            HADOOP_FOLDER=$(echo "$2" | sed 's/\/$//' )
            shift 2
        ;;
        '--help')
            help_message
        ;;
        *)
            help_message "Parameter '$1' Unrecognized"
        ;;
    esac
done

logger "${FUNCNAME[0]}" "INFO" "Starting script"
logger "${FUNCNAME[0]}" "INFO" "Build procces = $BUILD"
logger "${FUNCNAME[0]}" "INFO" "Setup procces = $SETUP"

# Settings java home
PROFILE_JAVAHOME="/etc/profile.d/java_home.sh"
PATH_JAVAHOME_11=$(alternatives --display java | grep 'slave jre:' | grep 'java-11' | awk '{print $NF}')
PATH_JAVAHOME_1_8=$(alternatives --display java | grep 'slave jre:' | grep 'java-1.8' | awk '{print $NF}')
logger "${FUNCNAME[0]}" "INFO" "Setting java home: JAVA_HOME=${PATH_JAVAHOME_1_8}"
echo "export JAVA_HOME=${PATH_JAVAHOME_1_8}" > "$PROFILE_JAVAHOME"
chmod +x "$PROFILE_JAVAHOME"
source "$PROFILE_JAVAHOME"
logger "${FUNCNAME[0]}" "INFO" "JAVA_HOME configured in $PROFILE_JAVAHOME"

# Installing requirements
if ! install_package "netcat wget git gcc gcc-c++ bzip2 java-1.8.0-openjdk java-1.8.0-openjdk-devel python3 mysql-connector-java";then
    logger "${FUNCNAME[0]}" "ERROR" "Error to install some package. Please install it manually and run script again."
    exit 1
fi

logger "${FUNCNAME[0]}" "INFO" "All packages installed successfully"

# Build proccess
if $P_BUILD;then
    logger "${FUNCNAME[0]}" "INFO" "Installing requirements"
    BUILD_PATH=$PWD

    # Installing Maven
    logger "${FUNCNAME[0]}" "INFO" "Installing Maven"
    if ! install_maven $BUILD_PATH;then
        logger "${FUNCNAME[0]}" "ERROR" "Please review installation proccess in official documentation https://maven.apache.org/install.html"
        exit 1
    fi
    logger "${FUNCNAME[0]}" "INFO" "Maven installed successfully"

    # Build Ranger
    logger "${FUNCNAME[0]}" "INFO" "Building Ranger"
    if ! build_ranger $BUILD_PATH;then
        logger "${FUNCNAME[0]}" "ERROR" "Please review installation proccess in official documentation https://ranger.apache.org/quick_start_guide.html"
        exit 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Ranger builded successfully"

fi

# FOLDERS GLOBAL VARIABLE
SOLR_VERSION=$(curl https://dlcdn.apache.org/lucene/solr/ 2>/dev/null | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1)
SOLR_URL="https://dlcdn.apache.org/lucene/solr/${SOLR_VERSION}"
if [ -z $RANGER_BUILDED_PATH ];then RANGER_BUILDED_PATH="./ranger";fi
RANGER_VERSION=$(cat "${RANGER_BUILDED_PATH}/target/version")

# folders schema
SOLR_FOLDER="${HADOOP_FOLDER}/solr/${SOLR_VERSION}"
SOLR_LOG_FOLDER="/var/log/solr"
RANGER_ADMIN_FOLDER="${HADOOP_FOLDER}/ranger-admin/${RANGER_VERSION}"
RANGER_ADMIN_LOG_FOLDER="/var/log/ranger/ranger-admin"
RANGER_ADMIN_CONF_FOLDER="/etc/ranger-admin"
RANGER_USERSYNC_FOLDER="${HADOOP_FOLDER}/ranger-usersync/${RANGER_VERSION}"
RANGER_USERSYNC_LOG_FOLDER="/var/log/ranger/ranger-usersync"
RANGER_USERSYNC_CONF_FOLDER="/etc/ranger-usersync"


if $P_UNINSTALL;then
    logger "${FUNCNAME[0]}" "INFO" "Uninstalling proccess"
    # Stopping solr
    CHK_SOLR_PROCCESS=$(ps faux | grep -v grep | grep Dsolr | wc -l)
    nc -zv localhost 6083 &>/dev/null
    CHK_PORT_ACESS=$?

    if [ $CHK_PORT_ACESS -eq 0 ] || [ $CHK_SOLR_PROCCESS -gt 0 ];then 
        logger "${FUNCNAME[0]}" "INFO" "Stopping solr"
        sh "${SOLR_FOLDER}/ranger_audit_server/scripts/stop_solr.sh"
    fi

    # Stopping Ranger admin
    CHK_RANGERADMIN_PROCCESS=$(ps faux | grep -v grep | grep Dproc_rangeradmin | wc -l)
    nc -zv localhost 6080 &>/dev/null
    CHK_PORT_ACESS=$?

    if [ $CHK_PORT_ACESS -gt 0 ] || [ $CHK_RANGERADMIN_PROCCESS -eq 0 ];then
        logger "${FUNCNAME[0]}" "INFO" "Stopping Ranger Admin"
        ranger-admin stop
    fi

    # Stopping Ranger usersync
    CHK_RANGERADMIN_PROCCESS=$(ps faux | grep -v grep | grep Dproc_rangerusersync | wc -l)
    nc -zv localhost 5151 &>/dev/null
    CHK_PORT_ACESS=$?

    if [ $CHK_PORT_ACESS -gt 0 ] || [ $CHK_RANGERADMIN_PROCCESS -eq 0 ];then
        logger "${FUNCNAME[0]}" "INFO" "Stopping Ranger Usersync"
        sh "${RANGER_USERSYNC_FOLDER}/ranger-usersync-services.sh" stop
    fi

    echo
    echo
    echo "MySQL"
    read -p "Type the MySQL hostname [default: localhost]: " MYSQL_HOST
    if [ -z $MYSQL_HOST ];then MYSQL_HOST="localhost";fi
    echo -n "Type the MySQL root password: "
    read -s MYSQL_ROOT_PASSWORD
    echo
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -h"$MYSQL_HOST" -e "SELECT 'Connection test.'" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Connection failed with root login. Review the root credentials or check the MySQL service."
        exit 1
    fi

    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<MYSQLSCRIPT &>/dev/null
    DROP DATABASE ranger
MYSQLSCRIPT

    rm -rf '/etc/ranger'
    rm -rf "${HADOOP_FOLDER}/solr"
    rm -rf "${HADOOP_FOLDER}/ranger-admin"
    rm -rf "${HADOOP_FOLDER}/ranger-usersync"
    rm -rf "${SOLR_LOG_FOLDER}"
    rm -rf "${RANGER_ADMIN_LOG_FOLDER}"
    rm -rf "${RANGER_USERSYNC_LOG_FOLDER}"

    clean_user_db

    logger "${FUNCNAME[0]}" "INFO" "Uninstalling proccess done"
fi

if $P_INSTALL;then

    # Getting data from terminal to setup proccess
    # MySQL
    # Getting root password as global variable
    logger "${FUNCNAME[0]}" "INFO" "Configuring MySQL to Ranger setup proccess"
    # new line
    echo
    echo
    if [ -z $MYSQL_ROOT_PASSWORD ];then
        echo "MySQL"
        read -p "Type the MySQL hostname [default: localhost]: " MYSQL_HOST
        if [ -z $MYSQL_HOST ];then MYSQL_HOST="localhost";fi
        echo -n "Type the MySQL root password: "
        read -s MYSQL_ROOT_PASSWORD
        echo
    fi
    
    # testing root login
    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -h"$MYSQL_HOST" -e "SELECT 'Connection test.'" &>/dev/null
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Connection failed with root login. Review the root credentials or check the MySQL service."
        exit 1
    fi
    # Run commands in MySQL
    # Getting new ranger credentials to MySQL
    read -p "New MySQL ranger username [default: rangerdba]: " MYSQL_RANGER_USERNAME
    if [ -z "$MYSQL_RANGER_USERNAME" ];then MYSQL_RANGER_USERNAME="rangerdba";fi
    echo -n "Type the password to [$MYSQL_RANGER_USERNAME]: "
    read -s MYSQL_RANGER_PASSWORD
    echo
    logger "${FUNCNAME[0]}" "INFO" "Creating the $MYSQL_RANGER_USERNAME user on MySQL"

    mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -h"$MYSQL_HOST" <<MYSQLSCRIPT &>/dev/null
CREATE USER IF NOT EXISTS '$MYSQL_RANGER_USERNAME'@'localhost' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'localhost' WITH GRANT OPTION;
CREATE USER  IF NOT EXISTS '$MYSQL_RANGER_USERNAME'@'$(hostname)' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'$(hostname)';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'$(hostname)' WITH GRANT OPTION;
CREATE USER  IF NOT EXISTS '$MYSQL_RANGER_USERNAME'@'$(hostname -i)' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'$(hostname -i)';
GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_RANGER_USERNAME'@'$(hostname -i)' WITH GRANT OPTION;
ALTER USER '$MYSQL_RANGER_USERNAME'@'localhost' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
ALTER USER '$MYSQL_RANGER_USERNAME'@'$(hostname)' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
ALTER USER '$MYSQL_RANGER_USERNAME'@'$(hostname -i)' IDENTIFIED BY '$MYSQL_RANGER_PASSWORD';
FLUSH PRIVILEGES;
MYSQLSCRIPT
    if [ $? -gt 0 ];then
        logger "${FUNCNAME[0]}" "ERROR" "Error to create MySQL credentials."
        logger "${FUNCNAME[0]}" "ERROR" "1 - Check MySQL service and connectivity."
        logger "${FUNCNAME[0]}" "ERROR" "2 - Verify the mysql.user table  'SELECT User,Host from mysql.user;'"
        logger "${FUNCNAME[0]}" "ERROR" "3 - Check the MySQL validate_password_policy 'SHOW VARIABLES LIKE 'validate_password_%';'"
        exit 1
    fi

    echo
    echo "Ranger passwords"
    echo -n "Ranger Admin password: "
    read -s RANGERADM_PASSWORD
    echo
    echo -n "Ranger Tagsync password: "
    read -s RANGER_TAGSYNC_PASSWORD
    echo
    echo -n "Ranger Usersync password: "
    read -s RANGER_USERSYNC_PASSWORD
    echo
    echo -n "Ranger Keyadmin password: "
    read -s RANGER_KEYADMIN_PASSWORD
    echo
    echo
    read -p "Ranger authenticate type [default: UNIX][LDAP]: " RANGER_AUTH_TYPE
    echo
    if [ -z "$RANGER_AUTH_TYPE" ];then RANGER_AUTH_TYPE="UNIX";fi
    RANGER_AUTH_TYPE=$(echo "$RANGER_AUTH_TYPE" | tr '[:lower:]' '[:upper:]')

    if [ ! $RANGER_AUTH_TYPE == 'UNIX' ] && [ ! $RANGER_AUTH_TYPE == 'LDAP' ];then
        logger "${FUNCNAME[0]}" "ERROR" "Athentication type $RANGER_AUTH_TYPE not valid or supported"
        exit 1
    fi

    if [ $RANGER_AUTH_TYPE == 'LDAP' ];then
        echo
        echo "LDAP config"
        read -p "LDAP URL [default: ldap://127.0.0.1:389]: " XA_LDAP_URL
        if [ -z $XA_LDAP_URL ];then XA_LDAP_URL='ldap://127.0.0.1:389';fi
        read -p "LDAP User search [exemple: ou=users,dc=xasecure,dc=net]: " LDAP_USER_SEARCH
        XA_LDAP_USERDNPATTERN="uid={0},${LDAP_USER_SEARCH}"
        XA_LDAP_GROUPSEARCHBASE="member=uid={0},${LDAP_USER_SEARCH}"
        read -p "LDAP Group Search Base [exemple: ou=groups,dc=xasecure,dc=net]: " XA_LDAP_GROUPSEARCHBASE
        read -p "LDAP Group Role Attribute [exemple: cn]: " XA_LDAP_GROUPROLEATTRIBUTE
        read -p "LDAP Base dn [exemple: dc=xasecure,dc=net]: " XA_LDAP_BASEDN
        read -p "LDAP User bind [exemple: cn=admin,ou=users,dc=xasecure,dc=net]: " XA_LDAP_USERBIND
        echo -n "LDAP User bind password: "
        read -s XA_LDAP_USERBIND_PASSWORD
        echo
        XA_LDAP_REFERRAL='follow'
        XA_LDAP_USERSEARCHFILTER="(uid={0})"

        if [ -z "$LDAP_USER_SEARCH" ] || \
         [ -z "$XA_LDAP_GROUPROLEATTRIBUTE" ] || \
         [ -z "$XA_LDAP_BASEDN" ] || \
         [ -z "$XA_LDAP_USERBIND" ];then
            logger "${FUNCNAME[0]}" "ERROR" "LDAP configuration ERROR. Configuration cannot be Empty."
            exit 1
        fi
        echo
    fi

    read -p "Hadoop conf path: " HADOOP_CONF_PATH
    if [ ! -d "$HADOOP_CONF_PATH" ];then
        logger "${FUNCNAME[0]}" "ERROR" "Path $HADOOP_CONF_PATH does not exist"
        exit 1
    fi
    HADOOP_CONF_PATH=$(echo "$HADOOP_CONF_PATH" | sed 's/\/$//' )
    if [ ! -f "${HADOOP_CONF_PATH}/core-site.xml" ] || [ ! -f "${HADOOP_CONF_PATH}/hdfs-site.xml" ];then
        logger "${FUNCNAME[0]}" "ERROR" "Path $HADOOP_CONF_PATH is not a valid Hadoop conf path."
        exit 1
    fi
    # new line
    echo
    echo

    logger "${FUNCNAME[0]}" "INFO" "MySQL configured successfully"

    logger "${FUNCNAME[0]}" "INFO" "Initializing setup ranger proccess"

    # Check Ranger builded folder
    if ! [ -f "${RANGER_BUILDED_PATH}/target/version" ];then
        logger "${FUNCNAME[0]}" "ERROR" "Something wrong with Ranger builded in ${RANGER_BUILDED_PATH}"
        logger "${FUNCNAME[0]}" "ERROR" "File ${RANGER_BUILDED_PATH}/target/version not found"
        exit 1
    fi

    # create folders
    logger "${FUNCNAME[0]}" "INFO" "Creating Ranger folders"
    if ! setup_ranger_folders;then
        logger "${FUNCNAME[0]}" "ERROR" "Error to create ranger folders."
        clean_user_db
        exit 1
    fi

    # install solr
    logger "${FUNCNAME[0]}" "INFO" "Installing solr"
    if ! setup_solr "${RANGER_BUILDED_PATH}";then
        logger "${FUNCNAME[0]}" "ERROR" "Error to install solr."
        #rm -rf "${HADOOP_FOLDER}/solr"
        kill -9 $(ps faux | grep -v grep | grep Dsolr| awk '{print $2}') &>/dev/null
        clean_user_db
        exit 1
    fi

    source "$PROFILE_JAVAHOME"

    # install Ranger admin
    logger "${FUNCNAME[0]}" "INFO" "Installing Ranger Admin"
    if ! setup_ranger_admin "${RANGER_BUILDED_PATH}";then
        logger "${FUNCNAME[0]}" "ERROR" "Error to install Ranger admin."
        rm -rf "${HADOOP_FOLDER}/ranger-admin"
        kill -9 $(ps faux | grep -v grep | grep Dproc_rangeradmin | awk '{print $2}') &>/dev/null
        clean_user_db
        exit 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Ranger Admin installed and started successfully"

    
     install ranger user sync
    logger "${FUNCNAME[0]}" "INFO" "Installing Ranger Usersync"
    if ! setup_ranger_usersync "${RANGER_BUILDED_PATH}";then
        logger "${FUNCNAME[0]}" "ERROR" "Error to install Ranger Usersync."
        rm -rf "${HADOOP_FOLDER}/ranger-usersync"
        kill -9 $(ps faux | grep -v grep | grep Dproc_rangerusersync| awk '{print $2}') &>/dev/null
        exit 1
    fi

    logger "${FUNCNAME[0]}" "INFO" "Ranger Usersync installed and started successfully"
    chown -R ranger: "${RANGER_ADMIN_FOLDER}"
    chown -R ranger: "${RANGER_ADMIN_LOG_FOLDER}"
    chown -R ranger: "${RANGER_USERSYNC_FOLDER}"
    chown -R ranger: "${RANGER_USERSYNC_LOG_FOLDER}"
fi