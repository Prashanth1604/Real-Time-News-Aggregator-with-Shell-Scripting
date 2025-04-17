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

# Show main menu
    CHOICE=$(dialog --clear \
        --backtitle "News App - Logged in as: $USERNAME" \
        --title "Main Menu" \
        --menu "Choose an option:" 20 50 15 \
        "${MENU_ITEMS[@]}" \
        3>&1 1>&2 2>&3)

    # Handle cancel/ESC
    [ -z "$CHOICE" ] && clean_exit

    # Process menu selection
    case "$CHOICE" in
        11) # Exit option
            clean_exit
            ;;

        9) # View Bookmarks
            # Get bookmarks with formatting
            BOOKMARKS=$(query_mysql "SELECT CONCAT('Title: ', title, '\nURL: ', url, '\nCategory: ', category, '\nBookmarked: ', bookmarked_at, '\n----------\n') FROM bookmarks WHERE userid='$USERID'")

            if [ -z "$BOOKMARKS" ]; then
                dialog --msgbox "No bookmarks found." 10 40
            else
                TEMP_FILE="/tmp/bookmarks-$$-${RANDOM}.txt"
                echo -e "YOUR BOOKMARKS:\n\n$BOOKMARKS" > "$TEMP_FILE"
                dialog --title "Your Bookmarks" --textbox "$TEMP_FILE" 20 80
                rm -f "$TEMP_FILE"
            fi
            ;;

        10) # View Analytics
            # Get user analytics data
            LAST_LOGIN=$(query_mysql "SELECT last_login FROM user_logins WHERE userid='$USERID'")
            VIEWS=$(query_mysql "SELECT COUNT(*) FROM user_activity WHERE userid='$USERID'")
            BOOKMARK_COUNT=$(query_mysql "SELECT COUNT(*) FROM bookmarks WHERE userid='$USERID'")
            TOP_CATEGORY=$(query_mysql "SELECT category FROM user_activity WHERE userid='$USERID' GROUP BY category ORDER BY COUNT(*) DESC LIMIT 1")

            # Handle empty results
            [ -z "$LAST_LOGIN" ] && LAST_LOGIN="First login"
            [ -z "$VIEWS" ] && VIEWS=0
            [ -z "$BOOKMARK_COUNT" ] && BOOKMARK_COUNT=0
            [ -z "$TOP_CATEGORY" ] && TOP_CATEGORY="None yet"

            # Format and display analytics
            TEMP_FILE="/tmp/analytics-$$-${RANDOM}.txt"
            cat > "$TEMP_FILE" << EOF
YOUR ACTIVITY STATISTICS:
------------------------
Username: $USERNAME
User ID: $USERID
Last Login: $LAST_LOGIN
Articles Viewed: $VIEWS
Bookmarks: $BOOKMARK_COUNT
Top Category: $TOP_CATEGORY

EOF

            # Add category breakdown if there's activity
            if [ "$VIEWS" -gt 0 ]; then
                echo "CATEGORY BREAKDOWN:" >> "$TEMP_FILE"
                echo "-------------------" >> "$TEMP_FILE"

                query_mysql "SELECT CONCAT(category, ': ', COUNT()) FROM user_activity WHERE userid='$USERID' GROUP BY category ORDER BY COUNT() DESC" >> "$TEMP_FILE"
            fi

            dialog --title "User Analytics" --textbox "$TEMP_FILE" 20 70
            rm -f "$TEMP_FILE"

            ;;



*)
            # Check if choice is within categories range
            if [[ "$CHOICE" -ge 1 && "$CHOICE" -le ${#CATEGORIES[@]} ]]; then
                CATEGORY="${CATEGORIES[$((CHOICE-1))]}"

                # Show loading message
                dialog --infobox "Fetching $CATEGORY news..." 5 40

                # Use curl with timeout to fetch news
                RESPONSE=$(curl -s -m 10 "${BASE_URL}?access_key=${API_KEY}&categories=${CATEGORY}&countries=${COUNTRIES}&languages=en&limit=10")

                # Check for curl errors
                if [ $? -ne 0 ]; then
                    dialog --msgbox "Failed to connect to news API. Please check your internet connection." 8 60
                    continue
                fi

                # Check for API errors
                if echo "$RESPONSE" | jq -e '.error' >/dev/null; then
                    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown API error"')
                    dialog --msgbox "API Error: $ERROR_MSG" 8 60
                    continue
                fi

                COUNT=$(echo "$RESPONSE" | jq '.data | length')

                if [ "$COUNT" -eq 0 ]; then
                    dialog --msgbox "No articles found for category: $CATEGORY" 8 50
                    continue
                fi

                # Build article selection menu
                ARTICLE_MENU=()
                for ((i=0; i<COUNT; i++)); do
                    TITLE=$(echo "$RESPONSE" | jq -r ".data[$i].title" | cut -c1-80)
                    ARTICLE_MENU+=($i "$TITLE")
                done

                # Show article selection menu
                IDX=$(dialog --menu "Select a $CATEGORY article" 20 70 15 "${ARTICLE_MENU[@]}" 3>&1 1>&2 2>&3)

                # Handle cancel action
                [ -z "$IDX" ] && continue

                # Extract article data
                ARTICLE=$(echo "$RESPONSE" | jq ".data[$IDX]")

                # Properly escape single quotes for SQL
                TITLE=$(echo "$ARTICLE" | jq -r .title)
                SAFE_TITLE="${TITLE//\'/\'\'}"

                URL=$(echo "$ARTICLE" | jq -r .url)
                SAFE_URL="${URL//\'/\'\'}"

                DESC=$(echo "$ARTICLE" | jq -r '.description // "No description available."')
                PUBLISHED=$(echo "$ARTICLE" | jq -r .published_at)

                # Record user activity
                execute_mysql "INSERT INTO user_activity (userid, title, category, viewed_at)
                    VALUES ('$USERID', '$SAFE_TITLE', '$CATEGORY', NOW());"

                # Show article action menu
                ACTION=$(dialog --menu "Choose action for article:" 15 60 3 \
                    1 "View" \
                    2 "Bookmark" \
                    3 "Back to menu" \
                    3>&1 1>&2 2>&3)

                # Handle cancel action
                [ -z "$ACTION" ] && continue

                case "$ACTION" in
                    1) # View article
                        TEMP_FILE="/tmp/article-$$-${RANDOM}.txt"
                        cat > "$TEMP_FILE" << EOF
ARTICLE DETAILS:
---------------
Title: $TITLE

Description: $DESC

Published: $PUBLISHED

URL: $URL

EOF
                        dialog --title "Article View" --textbox "$TEMP_FILE" 20 80
                        rm -f "$TEMP_FILE"
                        ;;

                    2) # Bookmark article
                        execute_mysql "INSERT INTO bookmarks (userid, username, title, url, category, published_at)
                            VALUES ('$USERID', '$SAFE_USERNAME', '$SAFE_TITLE', '$SAFE_URL', '$CATEGORY', '$PUBLISHED')"

                        if [ $? -eq 0 ]; then
                            dialog --msgbox "Article successfully bookmarked!" 8 40
                        else
                            dialog --msgbox "Failed to bookmark article. Please try again." 8 50
                        fi
                        ;;

                    3) # Back to menu
                        continue
                        ;;
                esac
            else
                dialog --msgbox "Invalid option selected." 8 40
            fi
            ;;
    esac
done
=======
            ;;    

