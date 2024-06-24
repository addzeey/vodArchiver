#!/bin/bash

# Initialize environment variables (for testing purposes, you can hard-code values here)
BUNNY_STREAM_LIBRARY_ID=259705
BUNNY_STREAM_API_KEY=0f66c2aa-c83a-4dd0-83829baafe2c-21d7-4e9c
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/1253381821622915173/z4LCAMvYzwqOsQXpuyPxecPZ-rZufPjnNBjx0Rd1tKtXstIXgBqkvXxW0xzEbOmHncKt

# Load environment variables from .env file if it exists (overrides hard-coded values if present)
if [ -f .env ]; then
  while IFS='=' read -r key value; do
    if [[ $key != \#* ]]; then
      export "$key=$value"
    fi
  done < .env
fi

# Check if necessary environment variables are set
if [ -z "$BUNNY_STREAM_LIBRARY_ID" ]; then
  echo "Error: BUNNY_STREAM_LIBRARY_ID is not set."
  exit 1
fi

if [ -z "$BUNNY_STREAM_API_KEY" ]; then
  echo "Error: BUNNY_STREAM_API_KEY is not set."
  exit 1
fi

if [ -z "$DISCORD_WEBHOOK_URL" ]; then
  echo "Error: DISCORD_WEBHOOK_URL is not set."
  exit 1
fi

# Check if file path argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <path-to-video-file>"
  exit 1
fi

FILE_PATH="$1"

# Function to send a message to Discord webhook
send_discord_message() {
  local message=$1
  curl -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    $DISCORD_WEBHOOK_URL
}

# Function to upload video to Bunny Stream
upload_to_bunny_stream() {
  local file_path=$1
  local max_retries=5
  local attempt=1

  # Create the video object
  local response=$(curl --silent --request POST \
    --url https://video.bunnycdn.com/library/259705/videos \
    --header "AccessKey: 0f66c2aa-c83a-4dd0-83829baafe2c-21d7-4e9c" \
    --header 'accept: application/json' \
    --header 'content-type: application/json' \
    --data "{\"title\":\"test_upload\"}")

  echo "Response from video creation: $response" # Debugging line

  local videoId=$(echo $response | jq -r '.guid')

  echo "Video ID: $videoId" # Debugging line

  if [ "$videoId" == "null" ] || [ -z "$videoId" ]; then
    echo "Error: Failed to create video object."
    send_discord_message "Error: Failed to create video object."
    return 1
  fi

  while [ $attempt -le $max_retries ]; do
    echo "Attempt $attempt to upload the video to Bunny Stream..."
    echo "attempteding to upload video id $videoId" # Debugging line
    echo "Uploading to URL: https://video.bunnycdn.com/library/$BUNNY_STREAM_LIBRARY_ID/videos/$videoId" # Debugging line

    response=$(curl --write-out "%{http_code}" --silent --output /dev/null --request PUT \
      --url https://video.bunnycdn.com/library/259705/videos/$videoId \
      --header "AccessKey: 0f66c2aa-c83a-4dd0-83829baafe2c-21d7-4e9c" \
      --header 'accept: application/json' \
      --data-binary @$file_path)

    if [ $response -eq 200 ]; then
      echo "Upload completed successfully on attempt $attempt."
      send_discord_message "Upload of video completed successfully on attempt $attempt."
      return 0
    else
      echo "Failed to upload the video on attempt $attempt. HTTP status code: $response"
      send_discord_message "Attempt $attempt to upload video failed with status code $response."
      ((attempt++))
      sleep 5
    fi
  done

  echo "Failed to upload the video after $max_retries attempts."
  send_discord_message "Failed to upload video after $max_retries attempts."
  return 1
}

# Test script: Upload a video file
if [ -f "$FILE_PATH" ]; then
  echo "Starting upload test for file: $FILE_PATH"
  upload_to_bunny_stream "$FILE_PATH"
else
  echo "Error: File $FILE_PATH does not exist."
  exit 1
fi