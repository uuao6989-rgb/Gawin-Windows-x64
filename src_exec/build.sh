#!/bin/bash
# Minimal Linux shell version of build.bat
# Compiles your cross-toolchain compiler components and exits immediately on error tokens.

clang++ -std=c++17 -O2 glld.cpp -o ../bin/glld || exit $?
clang++ -std=c++17 -O2 gstdo.cpp -o ../bin/gstdo || exit $?
clang++ -std=c++17 -O2 timer.cpp -o ../bin/timer || exit $?
clang++ -std=c++17 -O2 gfree.cpp -o ../bin/gfree || exit $?

echo "Built Linux executables in $(cd "$(dirname "$0")" && pwd)"