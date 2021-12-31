id: 86gq5kz04nyy4e7eq2njytvqivd2unre6i965ol3p5gz7cw3
name: requestz
main: src/main.zig
license: 0BSD
description: HTTP client for Zig 🦎
root_dependencies:
   - src: git https://github.com/ducdetronquito/iguanaTLS
   - src: git https://github.com/MasterQ32/zig-network commit-b9c5282
   - src: git https://github.com/ducdetronquito/http branch-release/0.2.0
   - src: git https://github.com/ducdetronquito/h11 branch-release/0.2.0

dependencies:
   - src: git https://github.com/ducdetronquito/iguanaTLS
   - src: git https://github.com/MasterQ32/zig-network commit-b9c5282
   - src: git https://github.com/ducdetronquito/http branch-release/0.2.0
   - src: git https://github.com/ducdetronquito/h11 branch-release/0.2.0
