import hashlib, pathlib, re, subprocess, sys
binary = str(pathlib.Path(sys.argv[1]).resolve())
source = pathlib.Path(sys.argv[2])
out = pathlib.Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
def capture(args, name, persist=True):
    p = subprocess.run([binary, *args], capture_output=True, text=True)
    if p.returncode: raise SystemExit((args, p.returncode, p.stderr))
    value = re.sub(r'\[env: ARC_SANDBOX=[^\n]*\]', '[env: ARC_SANDBOX=<sandbox>]', p.stdout)
    if persist: (out / name).write_text(value)
    return value
capture([], 'guide.txt')
capture(['--version'], 'version.txt')
env = subprocess.run([binary, 'env'], capture_output=True, text=True).stdout
(out / 'build.txt').write_text(next(line for line in env.splitlines() if line.startswith('# arc build:')) + '\n')
(out / 'README.md').write_bytes((source / 'README.md').read_bytes())
queue = [[]]; seen = []; blocks = []
while queue:
    args = queue.pop(0)
    help_text = capture([*args, '--help'], '', persist=False)
    blocks.append('===== arc ' + (' '.join(args) + ' ' if args else '') + '--help =====\n' + help_text)
    seen.append(' '.join(args) or 'arc')
    commands = help_text.split('Commands:\n', 1)
    if len(commands) == 2:
        for line in commands[1].split('\nOptions:', 1)[0].splitlines():
            m = re.match(r'  ([a-z][a-z0-9-]*)\s', line)
            if m and m[1] != 'help': queue.append([*args, m[1]])
(out / 'help.txt').write_text('\n'.join(blocks))
(out / 'commands.txt').write_text('\n'.join(seen) + '\n')
(out / 'binary.sha256').write_text(hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest() + '\n')
print(len(seen), 'help surfaces captured')
