#!/bin/bash

# Loop through all the json files in the abis directory and copy
# them from the out directory

# Check if abis directory exists
if [ ! -d "abis" ]; then
    echo "Error: abis directory not found"
    exit 1
fi

# Check if out directory exists
if [ ! -d "../out" ]; then
    echo "Error: ../out directory not found"
    exit 1
fi

# Loop through all JSON files in the abis directory
for abi_file in abis/*.json; do
    # Check if the file exists (in case no .json files are found)
    if [ ! -f "$abi_file" ]; then
        echo "No JSON files found in abis directory"
        exit 0
    fi
    
    # Extract the filename without extension and directory
    filename=$(basename "$abi_file" .json)
    
    # Construct the source path in the out directory
    source_path="../out/${filename}.sol/${filename}.json"
    
    # Check if the source file exists
    if [ -f "$source_path" ]; then
        echo "Extracting ABI from $source_path to $abi_file"
        jq '.abi' "$source_path" > "$abi_file"
    else
        echo "Warning: Source file $source_path not found"
    fi
done

echo "ABI update complete!"
