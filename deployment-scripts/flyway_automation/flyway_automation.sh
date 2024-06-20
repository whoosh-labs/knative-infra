#!/bin/sh

# Define variables
db_name="testing_platform"
sql_file="src/main/resources/db/migration/base_migration_import.sql"
envname="prod"
maven_version="3.9.6-r0"

# Check if required arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <git_pat> <mysql_user> <mysql_password> <mysql_url>"
    exit 1
fi

# Assign arguments to variables
git_pat=$1
mysql_user=$2
mysql_password=$3
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
apk add --no-cache wget

# Maven Installation if required
if ! command -v mvn &>/dev/null; then
    echo "Maven is not installed. Installing..."

    # Install Maven
    apk add --no-cache "maven=$maven_version"

    # Verify installation
    if ! command -v mvn &>/dev/null; then
        echo "Error: Maven installation failed"
        exit 1
    fi
fi

# Install property-manager-java-services
git clone "https://$git_pat@github.com/whoosh-labs/property-manager-java-services.git"
cd property-manager-java-services
git checkout production
mvn clean install -DskipTests
cd ..

# Install java-storage-library
git clone "https://$git_pat@github.com/whoosh-labs/java-storage-library.git"
cd java-storage-library
git checkout production
mvn clean install -U
cd ..

# Install testing-platform-backend
git clone "https://$git_pat@github.com/whoosh-labs/testing-platform-backend.git"
cd testing-platform-backend
git checkout production
mvn clean install -DskipTests

# Check if SQL file exists
if [ ! -f "$sql_file" ]; then
    echo "Error: $sql_file not found in the repository"
    exit 1
fi

# Connect to MySQL and create database
echo "Creating MySQL database '$db_name'..."
sed -i -E 's/^(SET.*)/-- \1/' "$sql_file"
mysql -u"$mysql_user" -p"$mysql_password" -h "$mysql_url" -e "CREATE DATABASE IF NOT EXISTS $db_name; USE $db_name; source $sql_file;" || { echo "Error: Failed to create database"; exit 1; }

echo "Executing $sql_file in '$db_name' database..."
mysql -u"$mysql_user" -p"$mysql_password" -h "$mysql_url" "$db_name" < "$sql_file" || { echo "Error: Failed to execute SQL file"; exit 1; }

# Write MySQL connection details to env file
echo "MYSQL_USERNAME=${mysql_user}" >> "${envname}.db.ini"
echo "MYSQL_PASSWORD=${mysql_password}" >> "${envname}.db.ini"
echo "MYSQL_URL=${mysql_url}:3306" >> "${envname}.db.ini"

bash flyway_migrate.sh --env "${envname}"

# Clearing directories
cd ..
rm -rf property-manager-java-services java-storage-library testing-platform-backend

echo "Script executed successfully."
