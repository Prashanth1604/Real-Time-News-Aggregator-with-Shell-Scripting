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


case "$AUTH_CHOICE" in
    1)
        USERNAME=$(dialog --inputbox "Enter your username to login:" 8 40 3>&1 1>&2 2>&3)
        [ -z "$USERNAME" ] && clean_exit

        # Escape single quotes in the username
        SAFE_USERNAME="${USERNAME//\'/\'\'}"
        USERID=$(query_mysql "SELECT userid FROM users WHERE username='$SAFE_USERNAME' LIMIT 1")

        if [ -z "$USERID" ]; then
            dialog --msgbox "User '$USERNAME' not found. Please register." 8 40
            clear
            exit 1
        fi
        ;;
    2)
        USERNAME=$(dialog --inputbox "Choose a username to register:" 8 40 3>&1 1>&2 2>&3)
        [ -z "$USERNAME" ] && clean_exit

        # Validate username - only allow alphanumeric and some special chars
        if ! [[ "$USERNAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            dialog --msgbox "Username contains invalid characters. Use only letters, numbers, and _.-" 8 60
            clear
            exit 1
        fi

        # Escape single quotes in the username
        SAFE_USERNAME="${USERNAME//\'/\'\'}"
        EXISTS=$(query_mysql "SELECT COUNT(*) FROM users WHERE username='$SAFE_USERNAME'")

        if [ "$EXISTS" -gt 0 ]; then
            dialog --msgbox "Username already taken. Try again." 8 40
            clear
            exit 1
        fi

        # Generate UUID for userid
        if command -v uuidgen &>/dev/null; then
            USERID=$(uuidgen)
        else
            USERID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
        fi

        execute_mysql "INSERT INTO users (userid, username) VALUES ('$USERID', '$SAFE_USERNAME')" || exit 1
        dialog --msgbox "Registration successful!" 8 40
        ;;
    *)
        clean_exit
        ;;
esac

# Update login time
execute_mysql "INSERT INTO user_logins (userid, last_login) VALUES ('$USERID', NOW())
    ON DUPLICATE KEY UPDATE last_login = NOW();" || exit 1

while true; do
    # Build menu with categories and options
    MENU_ITEMS=()
    for i in "${!CATEGORIES[@]}"; do
        MENU_ITEMS+=($((i+1)) "${CATEGORIES[$i]}")
    done
    MENU_ITEMS+=(9 "View Bookmarks")
    MENU_ITEMS+=(10 "View Analytics")
    MENU_ITEMS+=(11 "Exit")

    
