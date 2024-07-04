#!/bin/bash

set -x

sudo apt-get install -y curl mysql-client unzip jq git-all

# Define variables
db_name="testing_platform"
sql_file="src/main/resources/db/migration/base_migration_import.sql"
envname="minikube"
maven_version="3.6.3"

# Check if required arguments are provided
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <git_pat> <mysql_user> <mysql_password> <mysql_url> <mysql_port>"
    exit 1
fi

# Assign arguments to variables
git_pat=$1
mysql_user=$2
mysql_password=$3
mysql_url=$4
mysql_port=$5

# Check if Java 17 is installed
if command -v java &>/dev/null && [[ $(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d '.' -f 1) == "17" ]]; then
  echo "Java 17 is already installed."
else
  echo "Java 17 is not installed. Installing..."

  # Install OpenJDK 17
  sudo apt-get update
  sudo apt-get install -y openjdk-17-jdk openjdk-17-jre 

  # Verify installation
  if ! command -v java &>/dev/null || [[ $(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d '.' -f 1) != "17" ]]; then
    echo "Error: Java installation failed"
    exit 1
  fi
fi

# Maven Installation if required
maven_install_dir="/opt/apache-maven-${maven_version}"

mvn_version=$(mvn -v | grep "Apache Maven ${maven_version}")
if [ -z "$mvn_version" ]; then
    echo "Maven ${maven_version} is not installed. Installing..."
    maven_download_url="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${maven_version}/apache-maven-${maven_version}-bin.tar.gz"

    # Download Maven
    wget "$maven_download_url" -P /tmp || { echo "Error: Failed to download Maven"; exit 1; }

    # Extract Maven
    sudo tar xf /tmp/apache-maven-${maven_version}-bin.tar.gz -C /opt || { echo "Error: Failed to extract Maven"; exit 1; }

    # Set Maven environment variables
    echo 'export M2_HOME="${maven_install_dir}"' >> ~/.bashrc
    echo 'export PATH=\"\$PATH:${maven_install_dir}/bin"' >> ~/.bashrc

    # Set Maven environment variables
    export M2_HOME="$maven_install_dir"
    export PATH="$PATH:$M2_HOME/bin"

    # Verify installation
    mvn_version=$(mvn -v | grep "Apache Maven ${maven_version}")
    if [ -z "$mvn_version" ]; then
        echo "Error: Maven installation failed"
        exit 1
    fi
fi

# Install property-manager-java-services
git clone https://$git_pat@github.com/whoosh-labs/property-manager-java-services.git
cd property-manager-java-services
git checkout production
mvn clean install -DskipTests
cd ..

# Install java-storage-library
git clone https://$git_pat@github.com/whoosh-labs/java-storage-library.git
cd java-storage-library
git checkout production
mvn clean install -U
cd ..

# Install testing-platform-backend
git clone https://$git_pat@github.com/whoosh-labs/testing-platform-backend.git
cd testing-platform-backend
git checkout production
#mvn clean install -DskipTests

# Check if SQL file exists
if [ ! -f "$sql_file" ]; then
    echo "Error: $sql_file not found in the repository"
    exit 1
fi

# Connect to MySQL and create database
echo "Creating MySQL database '$db_name'..."
sed -i -E 's/^(SET.*)/-- \1/' $sql_file
mysql -u"$mysql_user" -p"$mysql_password" -h "$mysql_url" -P "$mysql_port" -e "CREATE DATABASE IF NOT EXISTS $db_name; USE $db_name; source $sql_file;" || { echo "Error: Failed to create database"; exit 1; }

echo "Executing $sql_file in '$db_name' database..."
mysql -u"$mysql_user" -p"$mysql_password" -h "$mysql_url" -P "$mysql_port" $db_name < "$sql_file" || { echo "Error: Failed to execute SQL file"; exit 1; }

# Write MySQL connection details to env file
echo "MYSQL_USERNAME=${mysql_user}" >> "${envname}.db.ini"
echo "MYSQL_PASSWORD=${mysql_password}" >> "${envname}.db.ini"
echo "MYSQL_URL=${mysql_url}:${mysql_port}" >> "${envname}.db.ini"

bash flyway_migrate.sh --env ${envname}

cd .. 
# Install platform api
git clone https://$git_pat@github.com/whoosh-labs/llm-platform-api.git
cd llm-platform-api
git checkout main
#mvn clean install -DskipTests



# Connect to MySQL and create database
echo "Creating MySQL database 'llm_platform'..."
mysql -u"$mysql_user" -p"$mysql_password" -h "$mysql_url" -P "$mysql_port" -e "CREATE DATABASE IF NOT EXISTS llm_platform; USE llm_platform;" || { echo "Error: Failed to create database"; exit 1; }

# Write MySQL connection details to env file
echo "MYSQL_USERNAME=${mysql_user}" >> "${envname}.db.ini"
echo "MYSQL_PASSWORD=${mysql_password}" >> "${envname}.db.ini"
echo "MYSQL_URL=${mysql_url}:${mysql_port}" >> "${envname}.db.ini"

bash flyway_migrate.sh --env ${envname}

# Clearing directories
cd ..
rm -rf property-manager-java-services java-storage-library testing-platform-backend llm-platform-api

echo "Script executed successfully."