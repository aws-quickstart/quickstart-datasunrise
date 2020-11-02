#!/bin/bash

###[ Variables ]###
AWS_EC2INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`
AWS_STACK_NAME="$CFUD_AWS_STACK_NAME"

DATASUNRISE_DBINSTANCE_NAME="DSI-$CFUD_AWS_STACK_NAME"
DATASUNRISE_PATH="/opt/datasunrise/"
DATASUNRISE_CLI_FILE_NAME="${DATASUNRISE_PATH}cmdline/executecommand.sh"
DATASUNRISE_LICENSE_FILE_NAME="appfirewall.reg"
DATASUNRISE_LOG_SETUP="/tmp/setup.log"
DATASUNRISE_SERVER_HOST=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
DATASUNRISE_SERVER_NAME="ds-$AWS_EC2INSTANCE_ID"
DATASUNRISE_SERVER_PORT="11000"

INSTALLER_FOLDER_TEMP="/tmp/dsif/"
INSTALLER_FILE_NAME="datasunrise_installer.run"
INSTALLER_LOG_INSTALL="/tmp/install.log"
INSTALLER_PATH="${INSTALLER_FOLDER_TEMP}${INSTALLER_FILE_NAME}"
INSTALLER_URL="https://update.datasunrise.com/get-last-datasunrise?cloud=aws"

###[ Functions ]###
aws_cli_configure() {
    AWS_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region'`
    aws configure set default.region $AWS_REGION
}

aws_secrets_retrieve() {
    aws_secrets_retrieve_dbaudit
    aws_secrets_retrieve_dbdictionary
    aws_secrets_retrieve_protected_instance
    aws_secrets_retrieve_license
    aws_secrets_retrieve_datasunrise_users
}

aws_secrets_retrieve_datasunrise_users() {
    # Admin
    AWS_ADMIN_PASSWORD_SECRET_NAME="secret-admin-password"
    AWS_ADMIN_SECRET_STRING=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_ADMIN_PASSWORD_SECRET_NAME --query SecretString --output text`
    DS_ADMIN_USER=`echo $AWS_ADMIN_SECRET_STRING | jq -r '.username'`
    DS_ADMIN_PASSWORD=`echo $AWS_ADMIN_SECRET_STRING | jq -r '.password'`

    # User
    AWS_USER_PASSWORD_SECRET_NAME="secret-user-password"
    AWS_USER_SECRET_STRING=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_USER_PASSWORD_SECRET_NAME --query SecretString --output text`
    DS_USER=`echo $AWS_USER_SECRET_STRING | jq -r '.username'`
    DS_USER_PASSWD=`echo $AWS_USER_SECRET_STRING | jq -r '.password'`
    DS_USER_PASSWD_HASH=(`echo -ne "$DS_USER_PASSWD" | md5sum`)
    DS_USER_EMAIL=`echo $AWS_USER_SECRET_STRING | jq -r '.email'`
}

aws_secrets_retrieve_dbaudit() {
    # Audit Database
    AWS_DBAUDIT_SECRET_NAME="secret-audit"
    AWS_DBAUDIT_SECRET_STRING=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_DBAUDIT_SECRET_NAME --query SecretString --output text`
    DS_DBAUDIT_TYPE="postgresql"
    DS_DBAUDIT_ADDRESS=`echo $AWS_DBAUDIT_SECRET_STRING | jq -r '.host'`
    DS_DBAUDIT_PORT=`echo $AWS_DBAUDIT_SECRET_STRING | jq -r '.port'`
    DS_DBAUDIT_NAME=`echo $AWS_DBAUDIT_SECRET_STRING | jq -r '.dbname'`
    DS_DBAUDIT_USERNAME=`echo $AWS_DBAUDIT_SECRET_STRING | jq -r '.username'`
    DS_DBAUDIT_PASSWORD=`echo $AWS_DBAUDIT_SECRET_STRING | jq -r '.password'`
}

aws_secrets_retrieve_dbdictionary() {
    # Dictionary Database
    AWS_DBDICTIONARY_SECRET_NAME="secret-dictionary"
    AWS_DBDICTIONARY_SECRET_STRING=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_DBDICTIONARY_SECRET_NAME --query SecretString --output text`
    DS_DBDICTIONARY_TYPE="postgresql"
    DS_DBDICTIONARY_ADDRESS=`echo $AWS_DBDICTIONARY_SECRET_STRING | jq -r '.host'`
    DS_DBDICTIONARY_PORT=`echo $AWS_DBDICTIONARY_SECRET_STRING | jq -r '.port'`
    DS_DBDICTIONARY_NAME=`echo $AWS_DBDICTIONARY_SECRET_STRING | jq -r '.dbname'`
    DS_DBDICTIONARY_USERNAME=`echo $AWS_DBDICTIONARY_SECRET_STRING | jq -r '.username'`
    DS_DBDICTIONARY_PASSWORD=`echo $AWS_DBDICTIONARY_SECRET_STRING | jq -r '.password'`
}

aws_secrets_retrieve_license() {
    # DataSunrise License
    AWS_LICENSE_SECRET_NAME="secret-license"
    DS_LICENSE=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_LICENSE_SECRET_NAME --query SecretString --output text`
}

aws_secrets_retrieve_protected_instance() {
    # Redshift Cluster
    AWS_DBPROTECTED_SECRET_NAME="secret-redshift"
    AWS_DBPROTECTED_SECRET_STRING=`aws --region $AWS_REGION secretsmanager get-secret-value --secret-id $AWS_STACK_NAME-$AWS_DBPROTECTED_SECRET_NAME --query SecretString --output text`
    DS_DBPROTECTED_TYPE=$CFUD_AWS_INSTANCE_TYPE
    DS_DBPROTECTED_ADDRESS=`echo $AWS_DBPROTECTED_SECRET_STRING | jq -r '.host'`
    DS_DBPROTECTED_PORT=`echo $AWS_DBPROTECTED_SECRET_STRING | jq -r '.port'`
    DS_DBPROTECTED_NAME=`echo $AWS_DBPROTECTED_SECRET_STRING | jq -r '.dbname'`
    DS_DBPROTECTED_USERNAME=`echo $AWS_DBPROTECTED_SECRET_STRING | jq -r '.username'`
    DS_DBPROTECTED_PASSWORD=`echo $AWS_DBPROTECTED_SECRET_STRING | jq -r '.password'`
}

installer_download() {
    mkdir -p $INSTALLER_FOLDER_TEMP
    wget -O $INSTALLER_PATH $INSTALLER_URL
}

installer_clean() {
    sudo rm -fr $INSTALLER_FOLDER_TEMP
}

installer_install() {
    sudo chmod +x $INSTALLER_PATH
    echo -ne "\n *** -----------------------------------------------------------\n Installing DataSunrise software\n"  >> $INSTALLER_LOG_INSTALL
    sudo $INSTALLER_PATH install --without-start --no-password -v -f \
    --remote-config \
    --dictionary-type $DS_DBDICTIONARY_TYPE \
    --dictionary-host $DS_DBDICTIONARY_ADDRESS \
    --dictionary-port $DS_DBDICTIONARY_PORT \
    --dictionary-database $DS_DBDICTIONARY_NAME \
    --dictionary-login $DS_DBDICTIONARY_USERNAME \
    --dictionary-password $DS_DBDICTIONARY_PASSWORD \
    --external-audit \
    --audit-type $DS_DBAUDIT_TYPE \
    --audit-host $DS_DBAUDIT_ADDRESS \
    --audit-port $DS_DBAUDIT_PORT \
    --audit-database $DS_DBAUDIT_NAME \
    --audit-login $DS_DBAUDIT_USERNAME \
    --audit-password $DS_DBAUDIT_PASSWORD \
    --server-name $DATASUNRISE_SERVER_NAME \
    --server-host $DATASUNRISE_SERVER_HOST \
    --server-port $DATASUNRISE_SERVER_PORT \
    --copy-proxies >> $INSTALLER_LOG_INSTALL 2>> $INSTALLER_LOG_INSTALL
    sleep 2
    echo -ne "\n *** -----------------------------------------------------------\n Setup DataSunrise Result : $?\n"  >> $INSTALLER_LOG_INSTALL
    echo -ne "\n *** -----------------------------------------------------------\n Installing license\n" >> $INSTALLER_LOG_INSTALL
    sudo echo $DS_LICENSE > ${DATASUNRISE_PATH}${DATASUNRISE_LICENSE_FILE_NAME} 2>> $INSTALLER_LOG_INSTALL
    sudo chown datasunrise:datasunrise ${DATASUNRISE_PATH}${DATASUNRISE_LICENSE_FILE_NAME} 2>> $INSTALLER_LOG_INSTALL
    echo -ne "\n *** -----------------------------------------------------------\n Starting DataSunrise\n" >> $INSTALLER_LOG_INSTALL
    sudo service datasunrise start 2>> $INSTALLER_LOG_INSTALL >> $INSTALLER_LOG_INSTALL
    sleep 30
    echo -ne "\n *** -----------------------------------------------------------\n Instalation done, now look at $DATASUNRISE_LOG_SETUP.\n" >> $INSTALLER_LOG_INSTALL
}

installer_postinstall() {
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$DATASUNRISE_PATH
    sudo chmod +x $DATASUNRISE_CLI_FILE_NAME
    echo -ne "\n *** -----------------------------------------------------------\n Attempting to connect as non-admin user\n" >> $DATASUNRISE_LOG_SETUP
    $DATASUNRISE_CLI_FILE_NAME connect -host 127.0.0.1 -port "$DATASUNRISE_SERVER_PORT" -login "$DS_USER" -password "$DS_USER_PASSWD" >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP

    # If the connection can't be established as a regular user, that means this is the first server of the cluster
    if [ $? != 0 ]; then
        echo -ne "\n *** -----------------------------------------------------------\n Non-admin user does not exist. Setup NEW node\n" >> $DATASUNRISE_LOG_SETUP
        export AF_HOME=$DATASUNRISE_PATH
        export AF_CONFIG=$DATASUNRISE_PATH
        ${DATASUNRISE_PATH}AppBackendService SET_ADMIN_PASSWORD="$DS_ADMIN_PASSWORD" >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Apply ADMIN password : $?\n" >> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Restarting DataSunrise\n" >> $DATASUNRISE_LOG_SETUP
        sudo service datasunrise restart 2>> $INSTALLER_LOG_INSTALL >> $INSTALLER_LOG_INSTALL
        sleep 30
        $DATASUNRISE_CLI_FILE_NAME connect -host 127.0.0.1 -port "$DATASUNRISE_SERVER_PORT" -login "$DS_ADMIN_USER" -password "$DS_ADMIN_PASSWORD" >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        DS_ROLE_JSON="{ \"id\":-1, \"name\":\"AWSUserRole\", \"activeDirectoryPath\":\"\", \"isSpecial\":false, \"permissions\":[[\"objectID\",\"actionIDList\"],[70,[]],[47,[]],[53,[]],[19,[]],[67,[]],[69,[]],[63,[]],[65,[]],[38,[]],[40,[]],[59,[2]],[30,[]],[29,[]],[11,[1,2,5]],[5,[1,2,3,4]],[3,[1,2,3,4]],[4,[1,2,3,4]],[50,[]],[22,[]],[33,[]],[51,[]],[2,[1,2,3,4]],[46,[]],[57,[]],[55,[]],[24,[]],[6,[]],[21,[]],[20,[]],[48,[]],[49,[]],[62,[1,2]],[45,[]],[44,[]],[16,[]],[64,[]],[17,[]],[18,[]],[34,[]],[23,[]],[32,[]],[8,[1,2,3,4]],[15,[]],[58,[]],[12,[]],[37,[]],[54,[]],[7,[1,2,3,4,5]],[27,[]],[28,[]],[56,[]],[66,[]],[26,[]],[61,[]],[25,[]],[9,[1,2,3,4]],[39,[]],[36,[]],[35,[]],[13,[]],[14,[]],[68,[]],[42,[]],[43,[]],[10,[1,2,3,4]],[60,[3,1,2]],[31,[]],[41,[]],[1,[]],[71,[]]] }"    
        echo -ne "\n *** -----------------------------------------------------------\n Add periodic task for removing stopped servers\n" >> $DATASUNRISE_LOG_SETUP
	    PER_TASK_JSON="{\"id\":-1,\"storePeriodType\":0,\"storePeriodValue\":0,\"name\":\"Dead EC2 instances removal\",\"type\":18,\"lastExecTime\":\"\",\"nextExecTime\":\"\",\"lastSuccessTime\":\"\",\"lastErrorTime\":\"\",\"serverID\":0,\"forceUpdate\":false,\"params\":{},\"frequency\":{\"minutes\":{\"beginDate\":\"2018-09-28 00:00:00\",\"repeatEvery\":10}},\"updateNextExecTime\":true}"
	    $DATASUNRISE_CLI_FILE_NAME arbitrary -function updatePeriodicTask -jsonContent "$PER_TASK_JSON" >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Role JSON\n$DS_ROLE_JSON\n" >> $DATASUNRISE_LOG_SETUP
        DS_ROLE_ID=`$DATASUNRISE_CLI_FILE_NAME arbitrary -function updateAccessRole -jsonContent "$DS_ROLE_JSON" | python -c "import sys, json; print json.load(sys.stdin)['id']"`
        DS_USER_JSON="{ \"id\":-1, \"login\":\"$DS_USER\", \"email\":\"$DS_USER_EMAIL\", \"roles\":[$DS_ROLE_ID], \"activeDirectoryAuth\":false, \"passwordHash\":\"$DS_USER_PASSWD_HASH\" }"
        echo -ne "\n *** -----------------------------------------------------------\n User JSON\n$DS_USER_JSON\n" >> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME arbitrary -function updateUser -jsonContent "$DS_USER_JSON" >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Add instance '$DATASUNRISE_DBINSTANCE_NAME'\n" >> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME addInstancePlus -name "$DATASUNRISE_DBINSTANCE_NAME" -dbType "$DS_DBPROTECTED_TYPE" -dbHost "$DS_DBPROTECTED_ADDRESS" -dbPort "$DS_DBPROTECTED_PORT" -database "$DS_DBPROTECTED_NAME" -login "$DS_DBPROTECTED_USERNAME" -password "$DS_DBPROTECTED_PASSWORD" -proxyHost 0.0.0.0 -proxyPort "$DS_DBPROTECTED_PORT" -savePassword ds 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Add DDL audit rule\n" >> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME addRule -action audit -name AuditRuleAdmin -logData true -filterType ddl -ddlSelectAll true -dbType "$DS_DBPROTECTED_TYPE" 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Add DML audit rule\n" >> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME addRule -action audit -name AuditRuleDML -logData true -dbType "$DS_DBPROTECTED_TYPE" 2>> $DATASUNRISE_LOG_SETUP

        # Additional settings and fine tune
        echo -ne "\n *** -----------------------------------------------------------\n Setup additional settings\n" >> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME changeParameter -name WebLoadBalancerEnabled -value 1 >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME changeParameter -name EnableAWSMetrics -value 1 >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME changeParameter -name MaxBackendMemory -value 10240 >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME changeParameter -name MaxCoreMemory -value 10240 >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        $DATASUNRISE_CLI_FILE_NAME changeParameter -name SetupWizardIsDone -value 1 >> $DATASUNRISE_LOG_SETUP 2>> $DATASUNRISE_LOG_SETUP
        echo -ne "\n *** -----------------------------------------------------------\n Restarting DataSunrise\n" >> $DATASUNRISE_LOG_SETUP
        sudo service datasunrise restart 2>> $INSTALLER_LOG_INSTALL >> $INSTALLER_LOG_INSTALL
        echo -ne "\n *** -----------------------------------------------------------\n Done!\n\n" >> $DATASUNRISE_LOG_SETUP
    fi
    $DATASUNRISE_CLI_FILE_NAME disConnect -f 2>> $DATASUNRISE_LOG_SETUP
}

installer_preinstall() {
    yum install java jq libtool-ltdl unixODBC -y
    wget -O /tmp/AmazonRedshiftODBC.rpm https://redshift-downloads.s3.amazonaws.com/drivers/odbc/1.4.8.1000/AmazonRedshiftODBC-64-bit-1.4.8.1000-1.x86_64.rpm
    yum --nogpgcheck localinstall /tmp/AmazonRedshiftODBC.rpm -y

    echo "[Amazon Redshift (x64)]" >> /etc/odbcinst.ini 
    echo "Description=Amazon Redshift ODBC Driver (64-bit)" >> /etc/odbcinst.ini 
    echo "Driver=/opt/amazon/redshiftodbc/lib/64/libamazonredshiftodbc64.so" >> /etc/odbcinst.ini 
}

###[ Main Script ]###
installer_preinstall
aws_cli_configure
installer_download
aws_secrets_retrieve
installer_install
installer_postinstall
installer_clean