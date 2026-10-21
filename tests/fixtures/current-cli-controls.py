#!/usr/bin/env python3
import json, sys
for line in sys.stdin:
    request = json.loads(line)
    params = request.get('params', {})
    result = {'method': request['method'], 'params': params, 'enabled': True, 'protocolVersion': 2, 'tools': params.get('tools', []), 'status': 'idle'}
    print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}), flush=True)
