(function () {
    var terminal = document.getElementById('terminal');

    var history = [];
    try {
        history = JSON.parse(localStorage["history"]);
    } catch (err) {
    }
    var histIdx = history.length;
    var histCurLine;

    var ws_url = location.protocol.replace('http', 'ws')+'//'+location.hostname+
        (location.port ? ':'+location.port: '')+'/ws/dmd';
    var conn = new WebSocket(ws_url);

    function handleKeyDown(e) {
        e = e || window.event;
        switch (e.keyCode || e.which)
        {
        case 38: // up
            if (histIdx == history.length)
                histCurLine = this.value;
            if (histIdx > 0)
                this.value = history[--histIdx];
            break;

        case 40: // down
            if (histIdx < history.length)
            {
                if (++histIdx == history.length)
                    this.value = histCurLine;
                else
                    this.value = history[histIdx];
            }
            break;

        case 13: case 14: // Return, Enter
            this.readOnly = true;
            history.push(this.value);
            histIdx = history.length;
            try {
                var tosave = history.slice(Math.max(0, history.length - 100));
                localStorage["history"] = JSON.stringify(tosave);
            } catch (err) {
            }
            conn.send(this.value);
            break;

        default:
            return;
        }
        e.preventDefault ? e.preventDefault() : e.returnValue = false;
    }

    function readline(prompt) {
        var line = document.createElement('div');
        line.classList.add('line');
        line.innerHTML =
            '<span class="text-info">'+prompt+'</span>'+
            '<input type="text" class="text-info" size="80" '+
                'autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />';
        var inp = line.lastChild;

        inp.onkeydown = handleKeyDown;
        terminal.appendChild(line);
        terminal.onclick = function () { inp.focus(); };
        inp.focus();
    }

    function writeln(type, line) {
        var respLn = document.createElement('div');
        respLn.innerHTML = '<span class="text-'+type+'">'+line+'</span>';
        terminal.appendChild(respLn);
    }

    conn.onopen = function (e) {
        readline('D> ');
    }

    conn.onmessage = function (e) {
        var resp = JSON.parse(e.data), prompt = 'D>&nbsp;';
        switch (resp.state)
        {
        case 'incomplete': prompt = '&nbsp;|&nbsp;'; break;
        case 'success':
        case 'error':
            for (var i = 0; i < resp.stdout.length; ++i)
                writeln('success', "=> "+resp.stdout[i]);
            for (var i = 0; i < resp.stderr.length; ++i)
                writeln('danger', "=> "+resp.stderr[i]);
            break;
        }
        readline(prompt);
    };

    var _hasErr = false;

    conn.onerror = function (e) {
        writeln('danger', 'A WebSocket error occured \''+e.data+'\'.');
    };

    conn.onclose = function (ce) {
        writeln('warning', 'Lost the connection to the server.');
    };
})();
