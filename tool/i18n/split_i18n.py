"""Split i18n/todo.json into i18n/batches/in-NN.json (about 250 items each)."""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 250


def main():
    i18n = os.path.join(ROOT, 'i18n')
    with open(os.path.join(i18n, 'todo.json'), encoding='utf-8') as f:
        todo = json.load(f)
    items = [('strings', k) for k in todo.get('strings', {})] + \
            [('templates', k) for k in todo.get('templates', {})]
    out_dir = os.path.join(i18n, 'batches')
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, 'in-*.json')):
        os.remove(old)
    count = 0
    for n, start in enumerate(range(0, len(items), SIZE), 1):
        batch = {'strings': {}, 'templates': {}}
        for kind, k in items[start:start + SIZE]:
            batch[kind][k] = ''
        with open(os.path.join(out_dir, f'in-{n:02d}.json'), 'w', encoding='utf-8', newline='\n') as f:
            json.dump(batch, f, ensure_ascii=False, indent=1)
            f.write('\n')
        count = n
    print(f'{len(items)} items -> {count} batches')


if __name__ == '__main__':
    main()
