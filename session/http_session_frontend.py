"""
HTTP Session Service
"""

import os, subprocess, sys, tempfile, time, urllib2

from sqlalchemy.exc import OperationalError

from flask import Flask, request
app = Flask(__name__)

app_port = 5000 # default

from http_session import post

import frontend_db_model as db

def launch_compute_session(url, output_url='debug'):
    """
    Launch a compute server listening on the given port, and return
    its UNIX process id and absolute path.
    """
    if output_url == 'debug':
        output_url = "http://localhost:%s/debug"%app_port
    execpath = tempfile.mkdtemp()
    args = ['python',
            'http_session.py',
            url, 
            'http://localhost:%s/ready/0'%app_port,
            output_url,
            execpath]
    pid = subprocess.Popen(args).pid
    t = time.time()
    return pid, execpath

def cleanup_sessions():
    S = db.session()
    sessions = S.query(db.Session).all()
    for z in sessions:
        try:
            print "Sending kill -9 signal to %s"%z.pid
            os.kill(z.pid, 9)
            if os.path.exists(z.path):
                shutil.rmtree(z.path)
        except:
            pass
        finally:
            S.delete(z)
            S.commit()
    
@app.route('/new_session')
def new_session():
    # TODO: add ability to specify the output url
    # TODO: we are assuming for now that compute session is on
    # localhost, but it could be on another machine.
    S = db.session()
    if S.query(db.Session).count() == 0:
        id = 0
        port = app_port + 1
    else:
        last_session = S.query(db.Session).order_by(db.Session.id.desc())[0]
        id = last_session.id + 1
        port = int(last_session.url.split(':')[-1]) + 1
        print last_session
    url = 'http://localhost:%s'%port
    print url
    pid, path = launch_compute_session(url)
    if pid == -1:
        return "fail"
    session = db.Session(id, pid, path, url)
    S.add(session)
    S.commit()
    return str(id)

@app.route('/execute/<int:id>', methods=['POST'])
def execute(id):
    if request.method == 'POST':
        if request.form.has_key('code'):
            code = request.form['code']
            try:
                post('http://localhost:5100', {'code':code})
                return 'ok'
            except urllib2.URLError:
                # session not started for some reason
                return 'error - no session'
    return 'error - nothing done'

@app.route('/ready/<int:id>')
def ready(id):
    return ''

@app.route('/interrupt/<int:id>')
def interrupt(id):
    return ''

@app.route('/status/<int:id>')
def status(id):
    return ''

@app.route('/put/<int:id>/<path>', methods=['POST'])
def put(id, path):
    return ''

@app.route('/get/<int:id>/<path>')
def get(id, path):
    return ''

@app.route('/delete/<int:id>/<path>')
def delete(id, path):
    return ''

@app.route('/files/<int:id>')
def files(id):
    return ''

@app.route('/debug', methods=['POST'])
def debug():
    if request.method == 'POST':
        print request.form
    return ''


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print "Usage: %s port"%sys.argv[0]
        sys.exit(1)

    db.create()
    cleanup_sessions()
    app_port = int(sys.argv[1])
    app.run(debug=True, port=app_port)
    
    # TODO: this is wrong below with the try/except, and
    # has something to do with how flask is threaded, maybe.
    try:
        cleanup_sessions()
    except:
        pass
    
