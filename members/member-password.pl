#!/usr/bin/perl
#script to set the password, and optionally a userid, for a borrower
#written 2/5/00
#by chris@katipo.co.nz
#converted to using templates 3/16/03 by mwhansen@hmc.edu

use strict;
use warnings;

use C4::Auth;
use Koha::AuthUtils;
use C4::Output;
use C4::Context;
use C4::Members;
use C4::Circulation;
use CGI qw ( -utf8 );
use C4::Members::Attributes qw(GetBorrowerAttributes);
use Koha::Token;

use Koha::Patrons;
use Koha::Patron::Categories;

my $input = new CGI;

my $theme = $input->param('theme') || "default";

# only used if allowthemeoverride is set

my ( $template, $loggedinuser, $cookie, $staffflags ) = get_template_and_user(
    {
        template_name   => "members/member-password.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { borrowers => 1 },
        debug           => 1,
    }
);

my $flagsrequired;
$flagsrequired->{borrowers} = 1;

my $member      = $input->param('member');
my $cardnumber  = $input->param('cardnumber');
my $destination = $input->param('destination');
my $newpassword  = $input->param('newpassword');
my $newpassword2 = $input->param('newpassword2');

my @errors;

my $patron = Koha::Patrons->find( $member );
unless ( $patron ) {
    print $input->redirect("/cgi-bin/koha/circ/circulation.pl?borrowernumber=$member");
    exit;
}

my $category_type = $patron->category->category_type;
my $bor = $patron->unblessed;

if ( ( $member ne $loggedinuser ) && ( $category_type eq 'S' ) ) {
    push( @errors, 'NOPERMISSION' )
      unless ( $staffflags->{'superlibrarian'} || $staffflags->{'staffaccess'} );

    # need superlibrarian for koha-conf.xml fakeuser.
}

push( @errors, 'NOMATCH' ) if ( ( $newpassword && $newpassword2 ) && ( $newpassword ne $newpassword2 ) );

my $minpw = C4::Context->preference('minPasswordLength');
push( @errors, 'SHORTPASSWORD' ) if ( $newpassword && $minpw && ( length($newpassword) < $minpw ) );

if ( $newpassword && !scalar(@errors) ) {

    die "Wrong CSRF token"
        unless Koha::Token->new->check_csrf({
            session_id => scalar $input->cookie('CGISESSID'),
            token  => scalar $input->param('csrf_token'),
        });

    my $digest = Koha::AuthUtils::hash_password( scalar $input->param('newpassword') );
    my $uid    = $input->param('newuserid') || $bor->{userid};
    my $dbh    = C4::Context->dbh;
    if ( Koha::Patrons->find( $member )->update_password($uid, $digest) ) {
        $template->param( newpassword => $newpassword );
        if ( $destination eq 'circ' ) {
            print $input->redirect("/cgi-bin/koha/circ/circulation.pl?findborrower=$cardnumber");
        }
        else {
            print $input->redirect("/cgi-bin/koha/members/moremember.pl?borrowernumber=$member");
        }
    }
    else {
        push( @errors, 'BADUSERID' );
    }
}
else {
    my $userid = $bor->{'userid'};

    my $chars              = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    my $length             = int( rand(2) ) + C4::Context->preference("minPasswordLength");
    my $defaultnewpassword = '';
    for ( my $i = 0 ; $i < $length ; $i++ ) {
        $defaultnewpassword .= substr( $chars, int( rand( length($chars) ) ), 1 );
    }

    $template->param( defaultnewpassword => $defaultnewpassword );
}

if ( $category_type eq 'C') {
    my $patron_categories = Koha::Patron::Categories->search_limited({ category_type => 'A' }, {order_by => ['categorycode']});
    $template->param( 'CATCODE_MULTI' => 1) if $patron_categories->count > 1;
    $template->param( 'catcode' => $patron_categories->next )  if $patron_categories->count == 1;
}

$template->param( adultborrower => 1 ) if ( $category_type =~ /^(A|I)$/ );

$template->param( picture => 1 ) if $patron->image;

if ( C4::Context->preference('ExtendedPatronAttributes') ) {
    my $attributes = GetBorrowerAttributes( $bor->{'borrowernumber'} );
    $template->param(
        ExtendedPatronAttributes => 1,
        extendedattributes       => $attributes
    );
}

$template->param(
    othernames                 => $bor->{'othernames'},
    surname                    => $bor->{'surname'},
    firstname                  => $bor->{'firstname'},
    borrowernumber             => $bor->{'borrowernumber'},
    cardnumber                 => $bor->{'cardnumber'},
    categorycode               => $bor->{'categorycode'},
    category_type              => $category_type,
    categoryname               => $bor->{'description'},
    address                    => $bor->{address},
    address2                   => $bor->{'address2'},
    streettype                 => $bor->{streettype},
    city                       => $bor->{'city'},
    state                      => $bor->{'state'},
    zipcode                    => $bor->{'zipcode'},
    country                    => $bor->{'country'},
    phone                      => $bor->{'phone'},
    phonepro                   => $bor->{'phonepro'},
    streetnumber               => $bor->{'streetnumber'},
    mobile                     => $bor->{'mobile'},
    email                      => $bor->{'email'},
    emailpro                   => $bor->{'emailpro'},
    branchcode                 => $bor->{'branchcode'},
    userid                     => $bor->{'userid'},
    destination                => $destination,
    is_child                   => ( $category_type eq 'C' ),
    minPasswordLength          => $minpw,
    RoutingSerials             => C4::Context->preference('RoutingSerials'),
    csrf_token                 => Koha::Token->new->generate_csrf({ session_id => scalar $input->cookie('CGISESSID'), }),
);

if ( scalar(@errors) ) {
    $template->param( errormsg => 1 );
    foreach my $error (@errors) {
        $template->param($error) || $template->param( $error => 1 );
    }
}

output_html_with_http_headers $input, $cookie, $template->output;
