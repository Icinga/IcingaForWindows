Describe 'Join-WebPath' {
    BeforeAll {
        Import-Module IcingaForWindows -Force -Global;
    }

    It 'Appends every single element of the request with leading http://' {
        $result = Join-WebPath -Path 'http://' -ChildPath '127.0.0.1:5000', 'my_index', '_doc?refresh=true'
        $result | Should Be 'http://127.0.0.1:5000/my_index/_doc?refresh=true'
    }

    It 'Appends segments and handles trailing "?" correctly' {
        $result = Join-WebPath -Path 'http://192.168.4.1' -ChildPath 'test','/test2','query?','ding'
        $result | Should Be 'http://192.168.4.1/test/test2/query?ding'
    }

    It 'Appends query starting with "?" directly and merges following parts' {
        $result = Join-WebPath -Path 'http://host' -ChildPath 'api','?q=','val'
        $result | Should Be 'http://host/api?q=val'
    }

    It 'Avoids double slashes when both sides have slashes' {
        $result = Join-WebPath -Path 'http://host/' -ChildPath '/api','/endpoint'
        $result | Should Be 'http://host/api/endpoint'
    }

    It 'Appends additional query params with & when query already exists' {
        $result = Join-WebPath -Path 'http://host' -ChildPath 'api','?q=1','param=2'
        $result | Should Be 'http://host/api?q=1&param=2'
    }

    It 'Skips empty child elements' {
        $result = Join-WebPath -Path 'http://host' -ChildPath 'api','', '/test'
        $result | Should Be 'http://host/api/test'
    }
}
