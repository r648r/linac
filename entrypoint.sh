#!/bin/bash

# Source the linac script to make the function available
. /app/linac.sh

# Execute the command passed to the container
exec "$@"