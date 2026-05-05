#!/bin/zsh
cd "$(dirname "$0")"
python3 -m http.server 23121 --bind 127.0.0.1
