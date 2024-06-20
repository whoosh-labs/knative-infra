#!/bin/sh

# Define variables
db_name="testing_platform"
sql_file="src/main/resources/db/migration/base_migration_import.sql"
envname="prod"
maven_version="3.6.3"

# Check if required arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <git_pat> <mysql_user> <mysql_password> <mysql_url>"
    exit 1
fi

# Assign arguments to variables
git_pat=$1
root_user=$2
root_password=$3
mysql_url=$4

# Check if Java 17 is installed
if command -v java &>/dev/null && [[ $(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d '.' -f 1) == "17" ]]; then
  echo "Java 17 is already installed."
else
  echo "Java 17 is not installed. Installing..."

  # Install OpenJDK 17
  apk update
  apk add openjdk17

  # Verify installation
  if ! command -v java &>/dev/null || [[ $(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d '.' -f 1) != "17" ]]; then
    echo "Error: Java installation failed"
    exit 1
  fi
fi

# Install wget
apk add --no-cache wget tar

# Maven Installation if required
if ! command -v mvn &>/dev/null; then
    echo "Maven is not installed. Installing..."

    # Download and install Maven 3.6.3
    mkdir -p /usr/share/maven
    wget -qO- "https://archive.apache.org/dist/maven/maven-3/$maven_version/binaries/apache-maven-$maven_version-bin.tar.gz" | tar zxvf - -C /usr/share/maven --strip-components=1
    ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

    # Verify installation
    if ! command -v mvn &>/dev/null; then
        echo "Error: Maven installation failed"
        exit 1
    fi
fi

# Install property-manager-java-services
git clone "https://$git_pat@github.com/whoosh-labs/property-manager-java-services.git"
cd property-manager-java-services
git checkout main
mvn clean install -DskipTests
cd ..

# Install java-storage-library
git clone "https://$git_pat@github.com/whoosh-labs/java-storage-library.git"
cd java-storage-library
git checkout main
mvn clean install -U
cd ..

# Install testing-platform-backend
git clone "https://$git_pat@github.com/whoosh-labs/testing-platform-backend.git"
cd testing-platform-backend
git checkout main
mvn clean install -DskipTests

# Check if SQL file exists
if [ ! -f "$sql_file" ]; then
    echo "Error: $sql_file not found in the repository"
    exit 1
fi

# Debugging: Test MySQL connection
echo "Testing MySQL connection..."
mysql -u"$root_user" -p"$root_password" -h "$mysql_url" -P 3306 -e "SHOW DATABASES;" || { echo "Error: Unable to connect to MySQL"; exit 1; }

# Connect to MySQL and create database
echo "Creating MySQL database '$db_name'..."
sed -i -E 's/^(SET.*)/-- \1/' "$sql_file"
mysql -u"$root_user" -p"$root_password" -h "$mysql_url" -e "CREATE DATABASE IF NOT EXISTS $db_name; USE $db_name; source $sql_file;" || { echo "Error: Failed to create database"; exit 1; }

echo "Executing $sql_file in '$db_name' database..."
mysql -u"$root_user" -p"$root_password" -h "$mysql_url" "$db_name" < "$sql_file" || { echo "Error: Failed to execute SQL file"; exit 1; }

# Write MySQL connection details to env file
echo "MYSQL_USERNAME=${root_user}" >> "${envname}.db.ini"
echo "MYSQL_PASSWORD=${root_password}" >> "${envname}.db.ini"
echo "MYSQL_URL=${mysql_url}:3306" >> "${envname}.db.ini"

bash flyway_migrate.sh --env "${envname}"

# Clearing directories
cd ..
rm -rf property-manager-java-services java-storage-library testing-platform-backend

echo "Script executed successfully."
