#!/bin/bash

input_file="main.lua"
output_file="ps5_lua_menu.lua"

temp_file="temp.lua"

send_mode=false
ip_address=""
port=""

if [[ "$1" == send:*:* ]]; then
    send_mode=true
    ip_port=${1#send:}
    ip_address=${ip_port%:*}
    port=${ip_port#*:}
fi

# Clear the output file
> "$temp_file"

while IFS= read -r line
do
  # Check if the line contains an HTML include directive
  if [[ $line =~ ([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\[\[html_include:([^]]+)\]\] ]]; then
    variable_name=${BASH_REMATCH[1]}
    html_path=${BASH_REMATCH[2]}
    
    if [[ -f $html_path ]]; then
      # Start the variable declaration
      echo "local $variable_name = [[" >> "$temp_file"
      
      # Append the contents of the HTML file
      cat "$html_path" >> "$temp_file"
      
      # Close the multiline string
      echo "]]" >> "$temp_file"
    else
      # If HTML file not found, add a comment and keep original line
      echo "-- HTML file $html_path not found" >> "$temp_file"
      echo "$line" >> "$temp_file"
    fi
  # Check if the line contains a require statement
  elif [[ $line =~ require\(\"([^\"]+)\"\) ]]; then
    module_path=${BASH_REMATCH[1]}
    module_file="$module_path.lua"
    if [[ -f $module_file ]]; then
      # Append the contents of the module file
      cat "$module_file" >> "$temp_file"
      echo "" >> "$temp_file"  # Add a newline
    else
      # If module file not found, keep the require line as comment
      echo "-- Module file $module_file not found" >> "$temp_file"
    fi
  else
    echo "$line" >> "$temp_file"
  fi
done < "$input_file"

mv "$temp_file" "$output_file"

echo "Combined Lua script created as $output_file"

if [ "$send_mode" = true ]; then
    if [ -f "send_lua.py" ]; then
        echo "Sending $output_file to $ip_address:$port..."
        python3 send_lua.py "$ip_address" "$port" "$output_file"
        if [ $? -eq 0 ]; then
            echo "Done!"
        else
            echo "Failed to send file. Check the connection and try again."
        fi
    else
        echo "Error: send_lua.py not found in the current directory."
        exit 1
    fi
fi
