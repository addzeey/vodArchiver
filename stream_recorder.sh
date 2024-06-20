#!/bin/bash
TIME_DATE='date +%d-%m-%y'
TIME_CLOCK='date +%H_%M_%S'
CC='date +%H:%M:%S''|'
# Check if necessary environment variables are set
if [ -z "$STREAMER_NAME" ]; then
  echo "Error: STREAMER_NAME is not set."
  exit 1
fi

if [ -z "$SUPABASE_URL" ]; then
  echo "Error: SUPABASE_URL is not set."
  exit 1
fi

if [ -z "$SUPABASE_API_KEY" ]; then
  echo "Error: SUPABASE_API_KEY is not set."
  exit 1
fi

if [ -z "$AZURE_ACCOUNT_NAME" ]; then
  echo "Error: AZURE_ACCOUNT_NAME is not set."
  exit 1
fi

if [ -z "$AZURE_ACCOUNT_KEY" ]; then
  echo "Error: AZURE_ACCOUNT_KEY is not set."
  exit 1
fi

if [ -z "$AZURE_CONTAINER_NAME" ]; then
  echo "Error: AZURE_CONTAINER_NAME is not set."
  exit 1
fi

if [ -z "$TWITCH_CLIENT_ID" ]; then
  echo "Error: TWITCH_CLIENT_ID is not set."
  exit 1
fi

if [ -z "$TWITCH_OAUTH_TOKEN" ]; then
  echo "Error: TWITCH_OAUTH_TOKEN is not set."
  exit 1
fi

# Construct the stream URL and info URL
STREAM_URL="twitch.tv/$STREAMER_NAME"
INFO_URL="https://tapi.livestream.tools/info/$STREAMER_NAME"

# Configure rclone for Azure Blob Storage if not already configured
RCLONE_CONFIG_PATH="/root/.config/rclone/rclone.conf"
if [ ! -f "$RCLONE_CONFIG_PATH" ]; then
  mkdir -p /root/.config/rclone
  cat <<EOF > "$RCLONE_CONFIG_PATH"
[azure]
type = azureblob
account = $AZURE_ACCOUNT_NAME
key = $AZURE_ACCOUNT_KEY
EOF
fi

# Directory of the script
SCRIPT_DIR=$(dirname "$0")

# Function to check if the stream is live
check_stream_live() {
  local title_response=$(curl -s "$INFO_URL")
  local stream_title=$(echo $title_response | jq -r .stream_title)

  if [ "$stream_title" != "null" ] && [ -n "$stream_title" ]; then
    echo $stream_title
    return 0
  else
    return 1
  fi
}

# Main loop to check stream status every minute
while true; do
  if check_stream_live; then
    FETCHED_TITLE=$(curl -s "$INFO_URL" | jq -r .stream_title)
    UNIQUE_ID=$(date +%s%N)  # Generate a unique ID based on current timestamp
    FILENAME="${UNIQUE_ID}"
    MP4_FILENAME="stream_${UNIQUE_ID}.mp4"
    TIME_DATE=$(date +%Y-%m-%dT%H:%M:%S)

    echo "$CC: Checking streamlink version..."
    streamlink --version
    echo "$CC: Stream is live, recording..."

    # Record the stream until it ends
    streamlink --twitch-api-header "Authorization=OAuth $OAUTH_TOKEN" \
        --twitch-disable-reruns \
        --twitch-disable-hosting \
        "https://www.twitch.tv/$STREAMER_NAME" best --stdout > "$SCRIPT_DIR/$FILENAME"
    # Verify the recording is successful and non-empty
    if [ -s "$SCRIPT_DIR/$FILENAME" ]; then
      echo "Stream recorded successfully, starting reencoding..."

      # Reencode the stream to MP4
      ffmpeg -i "$SCRIPT_DIR/$FILENAME" -codec:v libx264 -preset fast -crf 22 -codec:a aac -b:a 128k "$SCRIPT_DIR/$MP4_FILENAME"

      # If reencoding was successful
      if [ -f "$SCRIPT_DIR/$MP4_FILENAME" ]; then
        echo "Reencoding completed, uploading to Azure Blob Storage..."

        # Upload the reencoded file to Azure Blob Storage
        rclone copy "$SCRIPT_DIR/$MP4_FILENAME" "azure:$AZURE_CONTAINER_NAME"

        # Check if the upload was successful
        if [ $? -eq 0 ]; then
          echo "Upload completed successfully."

          # Send data to Supabase
          curl -X POST "$SUPABASE_URL" \
            -H "apikey: $SUPABASE_API_KEY" \
            -H "Authorization: Bearer $SUPABASE_API_KEY" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d "{
                  \"date\": \"$TIME_DATE\",
                  \"title\": \"$FETCHED_TITLE\",
                  \"blob_id\": \"$UNIQUE_ID\"
                }"

          # Remove the original and reencoded files after upload
          rm -f "$SCRIPT_DIR/$FILENAME"
          rm -f "$SCRIPT_DIR/$MP4_FILENAME"
        else
          echo "Failed to upload the file to Azure Blob Storage."
        fi
      else
        echo "Failed to reencode the stream."
      fi
    else
      echo "Recording failed or file is empty."
      rm -f "$SCRIPT_DIR/$FILENAME"
    fi
  else
    echo "Stream is not live, checking again in 1 minute..."
  fi
  sleep 60
done
