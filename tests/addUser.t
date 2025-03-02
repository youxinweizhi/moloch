# Test addUser.js and general authentication
use Test::More tests => 35;
use Test::Differences;
use Data::Dumper;
use MolochTest;
use JSON;
use strict;

viewerGet("/regressionTests/deleteAllUsers");
my $token = getTokenCookie();
my $es = "-o 'elasticsearch=$MolochTest::elasticsearch' -o 'usersElasticsearch=$MolochTest::elasticsearch' $ENV{INSECURE}";

# script exits successfully
my $result = system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser admin admin admin --admin");
eq_or_diff($result, "0", "script exited successfully");

# create a user with each flag
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser role:role role:role role:role --roles 'superAdmin' ");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test1 test1 test1");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test2 test2 test2 --apionly");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test3 test3 test3 --email");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test4 test4 test4 --expression 'ip.src == 10.0.0.1'");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test5 test5 test5 --remove");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test6 test6 test6 --webauth");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test7 test7 test7 --packetSearch");
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test8 test8 test8 --roles 'parliamentUser' ");

# fetch the users
my $users = viewerPost("/api/users", "");

# validate the flags
eq_or_diff($users->{recordsTotal}, 10, "Should have 10 users");
eq_or_diff($users->{data}->[0]->{roles}, from_json('["superAdmin"]'));
is($users->{data}->[1]->{userId}, 'role:role');
eq_or_diff($users->{data}->[2]->{roles}, from_json('["arkimeUser","cont3xtUser","parliamentUser","wiseUser"]'));
ok(!$users->{data}->[3]->{webEnabled}, "API only");
ok($users->{data}->[4]->{emailSearch}, "Email Search");
eq_or_diff($users->{data}->[5]->{expression}, "ip.src == 10.0.0.1");
ok($users->{data}->[6]->{removeEnabled}, "Remove");
ok($users->{data}->[7]->{headerAuthEnabled}, "Web auth");
ok($users->{data}->[8]->{packetSearch}, "Packet search");
eq_or_diff($users->{data}->[9]->{roles}, from_json('["parliamentUser"]'));

# user should have password
my $response = viewerGet("/regressionTests/getUser/test1");
ok(exists $response->{passStore}, "Users has password");

# --createOnly flag should not overwrite the user if it already exists
my $user8 = $users->{data}->[8];
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test7 test7 test7 --createOnly --email --remove --expression 'ip.src == 10.0.0.2'");
$users = viewerPost("/api/users", "");
eq_or_diff($users->{data}->[8], $user8, "Create only doesn't overwrite user");

# can update a user
my $user1 = $users->{data}->[2];
system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n testuser test1 test1 test1 --email");
$users = viewerPost("/api/users", "");
ok($users->{data}->[2]->{emailSearch}, "Can update exiting user");


#### Auth Header tests
my $mresponse;

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/");
is ($response->code, 401);
is ($response->content, 'Unauthorized');

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/", ':arkime_user' => '');
is ($response->code, 401);
is ($response->content, '{"success":false,"text":"User name header is empty"}');

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/", ':arkime_user' => 'authtest1');
is ($response->code, 200);

$response = viewerGet("/regressionTests/getUser/authtest1");
delete $response->{lastUsed};
$mresponse = multiGet("/regressionTests/getUser/authtest1");
delete $mresponse->{lastUsed};
eq_or_diff($response, $mresponse);

delete $response->{passStore};
eq_or_diff($response, from_json('{"headerAuthEnabled":true,"enabled":true,"userId":"authtest1","webEnabled":true,"removeEnabled":false,"userName":"authtest1","packetSearch":true,"emailSearch":true,"expression":"","settings":{},"roles":["arkimeUser","cont3xtUser","parliamentUser","wiseUser"]}'));

system("cd ../viewer ; node addUser.js $es -c ../tests/config.test.ini -n test3 authtest2 authtest2 authtest2");
$response = viewerGet("/regressionTests/getUser/authtest2");

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/", ':arkime_user' => 'authtest2');
is ($response->code, 200);

# Bad password
$MolochTest::userAgent->credentials( "$MolochTest::host:8126", 'Moloch', 'authtest2', 'authtest222' );
$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/");
is ($response->code, 401);

# Bad password but username header
$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/", ':arkime_user' => 'authtest2');
is ($response->code, 200);

# Good password
$MolochTest::userAgent->credentials( "$MolochTest::host:8126", 'Moloch', 'authtest2', 'authtest2' );
$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/");
is ($response->code, 200);

# No arkimeUser role
$MolochTest::userAgent->credentials( "$MolochTest::host:8126", 'Moloch', 'test8', 'test8' );
$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/");
is ($response->content, "Need arkimeUser role assigned");
is ($response->code, 200);

# No role auth
$MolochTest::userAgent->credentials( "$MolochTest::host:8126", 'Moloch', 'role:role', 'role:role' );
$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/");
is ($response->code, 403);
is ($response->content, '{"success":false,"text":"Can not authenticate with role"}');

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8126/", ':arkime_user' => 'role:role');
is ($response->code, 401);
is ($response->content, '{"success":false,"text":"Can not authenticate with role"}');

$response = $MolochTest::userAgent->get("http://$MolochTest::host:8123/?molochRegressionUser=role:role");
is ($response->code, 401);
is ($response->content, '{"success":false,"text":"Can not authenticate with role"}');


# cleanup
viewerDeleteToken("/api/user/role:role", $token);
viewerDeleteToken("/api/user/admin", $token);
viewerDeleteToken("/api/user/test1", $token);
viewerDeleteToken("/api/user/test2", $token);
viewerDeleteToken("/api/user/test3", $token);
viewerDeleteToken("/api/user/test4", $token);
viewerDeleteToken("/api/user/test5", $token);
viewerDeleteToken("/api/user/test6", $token);
viewerDeleteToken("/api/user/test7", $token);
viewerDeleteToken("/api/user/test8", $token);
viewerDeleteToken("/api/user/authtest1", $token);
viewerDeleteToken("/api/user/authtest2", $token);

my $users = viewerPost("/user/list", "");
is (@{$users->{data}}, 0, "Empty users table");
