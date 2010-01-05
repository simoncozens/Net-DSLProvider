use Test::More 'no_plan';
use Net::DSLProvider::Murphx;

my $account = Net::DSLProvider::Murphx->new({
    user => $ENV{MURPHX_USERNAME},
    pass => $ENV{MURPHX_PASSWORD},
    clientid => $ENV{MURPHX_CLIENTID},
    debug => 1
});
isa_ok($account, "Net::DSLProvider::Murphx");
isa_ok($account, "Net::DSLProvider");
is($account->user => $ENV{MURPHX_USERNAME});

like($account->request_xml(selftest => { sysinfo => { type => "module" }}), 
qr/<block name="sysinfo">\n<a name="type" format="text">module</,
"Request looks good");

like($account->request_xml(provide => {
    order => {
        attributes => { "fixed-ip" => "N" },
        "client-ref" => "test"
    },
    customer => { forename => "Test", surname => "User" } }), 
qr{<block name="customer">
<a name="forename" format="text">Test</a>
<a name="surname" format="text">User</a>
</block>
<block name="order">
<a name="client-ref" format="text">test</a>
<block name="attributes">
<a name="fixed-ip" format="yesno">N</a>
</block>
</block>
</Request>
},
    "Complex request looks good");
