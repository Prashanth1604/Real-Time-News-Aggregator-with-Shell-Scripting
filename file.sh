#!/bin/bash

# Load API key and DB credentials from environment or use defaults
API_KEY="${NEWS_API_KEY:-6b26fcac735584723de07ee21cff736e}"
BASE_URL="http://api.mediastack.com/v1/news"
COUNTRIES="us,gb,in"

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-theuser}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-test}"

CATEGORIES=("business" "entertainment" "general" "health" "science" "sports" "technology")

# Function to safely execute MySQL queries
execute_mysql() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$1"
    if [ $? -ne 0 ]; then
        dialog --msgbox "Database error occurred. Please try again." 8 40
        return 1
    fi
    return 0
}

# Function to safely query MySQL with output
query_mysql() {
    result=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -sse "$1")
    echo "$result"
}

# Check dependencies
for cmd in curl jq dialog mysql; do
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd is required but not installed."
        exit 1
    fi
done

# Clean exit function
clean_exit() {
    clear
    echo "Thank you for using the News App!"
    exit 0
}

# Login or Register
AUTH_CHOICE=$(dialog --menu "Choose an option:" 10 40 2 \
    1 "Login" \
    2 "Register" \
    3>&1 1>&2 2>&3)

# Exit if canceled
[ -z "$AUTH_CHOICE" ] && clean_exit
