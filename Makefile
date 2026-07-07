build:
	zig build -Dcpu=baseline -Doptimize=Debug -Dllvm=true
run:
	./zig-out/bin/magixwm "konsole"
build-run: build run

