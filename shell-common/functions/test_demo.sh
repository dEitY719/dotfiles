#!/bin/bash
# shell-common/functions/test_demo.sh
# Demo function for hook testing - FIXED

test_demo() {
    if [ $# -eq 0 ]; then
        # FIXED: using dash-form in error message
        ux_error "Usage: test-demo <argument>"
        return 1
    fi
}

alias test-demo='test_demo'
