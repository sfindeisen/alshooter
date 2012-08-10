#!/usr/bin/perl
#
# A very simple Allegro.pl auction shooter.
#
# Copyright (C) 2010 Stanislaw Findeisen <stf at eisenbits.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Changes history:
#
# 2010-02-03 (STF) Initial version.
# 2010-02-04 (STF) Password is now read from STDIN.

use warnings;
use strict;
use utf8;
use integer;

use constant {
    TTA_SECS_LOGIN => 30,
    TTA_SECS_BID   =>  3,

    # HTTP generic
    HTTP_HEADER_DATE     => 'Date',
    HTTP_HEADER_LOCATION => 'Location',
    HTTP_HEADER_REFRESH  => 'Refresh',
    HTTP_METHOD_POST     => 'POST',

    # HTML generic
    FI_checkbox      => 'checkbox',
    FI_hidden        => 'hidden',
    FI_password      => 'password',
    FI_radio         => 'radio',
    FI_submit        => 'submit',
    FI_text          => 'text',

    # LWP related
    LWP_COOKIE_FILENAME_DEFAULT => 'lwpcookies.txt',
    LWP_CLIENT_SSL_CIPHER       => 'Client-SSL-Cipher',
    LWP_CLIENT_SSL_CERT_SUBJECT => 'Client-SSL-Cert-Subject',
    LWP_CLIENT_SSL_CERT_ISSUER  => 'Client-SSL-Cert-Issuer',
    LWP_IF_SSL_CERT_SUBJECT     => 'If-SSL-Cert-Subject',

    # Calendar generic
    MONTH_JAN => 'Jan',
    MONTH_FEB => 'Feb',
    MONTH_MAR => 'Mar',
    MONTH_APR => 'Apr',
    MONTH_MAY => 'May',
    MONTH_JUN => 'Jun',
    MONTH_JUL => 'Jul',
    MONTH_AUG => 'Aug',
    MONTH_SEP => 'Sep',
    MONTH_OCT => 'Oct',
    MONTH_NOV => 'Nov',
    MONTH_DEC => 'Dec',
    TZ_CET    => 'CET',
    TZ_CEST   => 'CEST',

    # Allegro specific
    ALLEGRO_HOST_DOCROOT                  => 'http://allegro.pl/',
    ALLEGRO_HOST_SSL                      => 'ssl.allegro.pl',
    ALLEGRO_HOST_SSL_DOCROOT              => 'https://ssl.allegro.pl/',
    ALLEGRO_FORM_LOGIN_ACTION             => 'https://ssl.allegro.pl/login.php',
    ALLEGRO_FORM_LOGIN_REDIRECT_1         => qr/^\/direct_login.php\?/,
    ALLEGRO_FORM_LOGIN_REDIRECT_1_BADPASS => qr/^https:\/\/ssl.allegro.pl\/enter_login.php\?.*errmsg=Nieprawid%C5%82owa\+nazwa\+u%C5%BCytkownika\+lub\+has%C5%82o.*$/,
    ALLEGRO_FORM_LOGIN_REDIRECT_2         => qr/^0;URL=(http:\/\/allegro.pl\/direct_login.php\?.*)$/,
    ALLEGRO_FF_LOGIN_SESSION              => 'session',
    ALLEGRO_FF_LOGIN_GLOBAL_LOGIN_HASH    => 'global_login_hash',
    ALLEGRO_FF_LOGIN_SESSION_LOGIN_HASH   => 'session_login_hash',
    ALLEGRO_FF_LOGIN_URL                  => 'url',
    ALLEGRO_FF_LOGIN_REQUEST_SERVER       => 'request_server',
    ALLEGRO_FF_LOGIN_SUBMIT               => undef,
    ALLEGRO_FF_LOGIN_SUBMIT_VALUE         => 'Zaloguj się',
    ALLEGRO_FF_LOGIN_USER_LOGIN           => 'user_login',
    ALLEGRO_FF_LOGIN_USER_PASSWORD        => 'user_password',

    ALLEGRO_FORM_PREBID_ACTION            => 'http://allegro.pl/pre_bid.php',
    ALLEGRO_FF_PREBID_AMOUNT              => 'amount',
    ALLEGRO_FF_PREBID_ITEM_ID             => 'item_id',
    ALLEGRO_FF_PREBID_SUBMIT              => undef,
    ALLEGRO_FF_PREBID_SUBMIT_VALUE        => qr/^Licytuj/,
    ALLEGRO_FORM_BID_ACTION               => 'http://allegro.pl/bid.php',
    ALLEGRO_FORM_BID_REDIRECT             => qr/^\/post_bid.php\?/,
    ALLEGRO_FF_BID_AMOUNT                 => 'amount',
    ALLEGRO_FF_BID_ITEM_ID                => 'item_id',
    ALLEGRO_FF_BID_QUANTITY               => 'quantity',
    ALLEGRO_FF_BID_SUBMIT                 => undef,
    ALLEGRO_FF_BID_SUBMIT_VALUE           => qr/^Licytuj/,

    ALLEGRO_AUCTION_TITLE    => qr/<title>([^<>]*)- Aukcje internetowe Allegro<\/title>/,
    ALLEGRO_AUCTION_FINISHED => qr/^Zakończona$/,
    ALLEGRO_AUCTION_LASTCALL => qr/^Poniżej minuty$/,

    # auction deadline: (pon 01 lut 2010 09:39:01 CET)
    # These must be lower case! (see below)
    # TODO dobre nazwy?
    ALLEGRO_MONTH_JAN => 'sty',
    ALLEGRO_MONTH_FEB => 'lut',
    ALLEGRO_MONTH_MAR => 'mar',
    ALLEGRO_MONTH_APR => 'kwi',
    ALLEGRO_MONTH_MAY => 'maj',
    ALLEGRO_MONTH_JUN => 'cze',
    ALLEGRO_MONTH_JUL => 'lip',
    ALLEGRO_MONTH_AUG => 'sie',
    ALLEGRO_MONTH_SEP => 'wrz',
    ALLEGRO_MONTH_OCT => 'paź',
    ALLEGRO_MONTH_NOV => 'lis',
    ALLEGRO_MONTH_DEC => 'gru',

    VERSION      => '0.2',          # this is used in UA identification string
    VERSION_DATE => '2010-02-04'
};

use POSIX qw(strftime locale_h);
use Encode;

use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Date;
use HTML::Form;
use Time::Piece;

use Getopt::Long;
use IO::Prompt;

####################################
# Global variables
####################################

my $userAgent          = undef;                    # LWP::UserAgent
my $auctionId          = undef;
my $auctionTitle       = undef;
my $auctionEnd         = undef;                    # Unix time
my $auctionFinished    = 0;                        # auction is finished
my $auctionLastCall    = 0;                        # 1 minute before auction end (or later)
my $maxBid             = undef;
my $serverTime         = undef;                    # Unix time
my $userName           = undef;
my $userPassword       = undef;
my $cookieFileName     = undef;
my $request            = undef;                    # last HTTP request  to   the server
my $response           = undef;                    # last HTTP response from the server

####################################
# Common stuff
####################################

sub trim {
    my $s = shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub timeStampToStr {
    my $ts = shift;
    return strftime("%a, %d %b %Y %H:%M:%S %z %Z", gmtime($ts));
}

sub printPrefix {
    my $timeStr = timeStampToStr(time());
    my $prefix  = shift;
    unshift(@_, ($timeStr . ' '));
    unshift(@_, $prefix);

    my $msg = join('', @_);
    chomp($msg);
    $msg = encode('UTF-8', $msg);
    local $| = 1;
    print(STDERR "$msg\n");
}

sub debug {
    printPrefix('[alsh-debug] ', @_);
}

# level 2 debug
sub debug2 {
    printPrefix('[alsh-debug] ', @_);
}

sub debugTimes {
    my $msg = shift;
    my ($user, $system, $cuser, $csystem) = times();
    $msg = (defined($msg) ? ("($msg)") : '');
    debug("times $msg: $user/$system/$cuser/$csystem");
}

sub warning {
    printPrefix('[alsh-warn]  ', @_);
}

sub error {
    printPrefix('[alsh-error] ', @_);
}

sub info {
    printPrefix('[alsh-info]  ', @_);
}

sub fatal {
    error(@_);
    die(@_);
}

####################################
# HTTP general
####################################

sub create_user_agent {
    $userAgent = LWP::UserAgent->new;
    $userAgent->agent('alshooter ' . VERSION . ' ');
    $userAgent->cookie_jar(HTTP::Cookies->new(file => $cookieFileName, autosave => 1));
}

sub get_page {
    my $redirectUrl = shift;
    my $secure      = shift;
    debug("GET $redirectUrl");
    $request = HTTP::Request->new(GET => $redirectUrl);
    $request->header(LWP_IF_SSL_CERT_SUBJECT, ALLEGRO_HOST_SSL);
    debug2($request->as_string);
    $response = $userAgent->request($request);
}

sub updateServerTime {
    my $httpDate = $response->header(HTTP_HEADER_DATE);

    if ($httpDate) {
        my $httpDateTS = str2time($httpDate);
        debug("update server time: $httpDate => $httpDateTS");
        $serverTime = $httpDateTS;
    } else {
        warning("No HTTP Date header!");
    }
}

####################################
# Allegro related
####################################

my $g0_white       = '(?:[\s\n]*)';
my $g0_text        = '(?:[^<>]*)';
my $g1_text        = '([^<>]*)';
my $g0_paramName   = '[a-zA-Z]+';
my $g0_paramValue  = '[^"]*';
my $g0_param       = "(?:${g0_white}${g0_paramName}${g0_white}=${g0_white}\"${g0_paramValue}\"${g0_white})";
my $g0_params      = "(?:${g0_white}${g0_param}*)";

my $g0_br          = "(?:${g0_white}<br${g0_params}/>)";
my $g0_br_multi    = "(?:${g0_br}*)";
my $g0_b_o         = "(?:${g0_white}<b${g0_params}>)";
my $g0_font_o      = "(?:${g0_white}<font${g0_params}>)";
my $g0_span_o      = "(?:${g0_white}<span${g0_params}>)";
my $g0_b_om        = "(?:${g0_b_o}?)";
my $g0_font_om     = "(?:${g0_font_o}?)";
my $g0_span_om     = "(?:${g0_span_o}?)";
my $g0_b_c         = "(?:${g0_white}</b>)";
my $g0_font_c      = "(?:${g0_white}</font>)";
my $g0_span_c      = "(?:${g0_white}</span>)";
my $g0_b_cm        = "(?:${g0_b_c}?)";
my $g0_font_cm     = "(?:${g0_font_c}?)";
my $g0_span_cm     = "(?:${g0_span_c}?)";

my $g7_deadline_basic = "\\(\\w+ (\\d\\d) (\\w+) (\\d{4}) (\\d{1,2}):(\\d\\d):(\\d\\d) (\\w+)\\)";     # (pon 01 lut 2010 09:39:01 CET)
my $g8_deadline    = "<tr${g0_params}>${g0_white}<td${g0_params}>Do końca</td>${g0_white}<td${g0_params}>${g0_b_om}${g0_font_om}${g1_text}${g0_font_cm}${g0_b_cm}${g0_br}${g0_span_om}${g7_deadline_basic}${g0_span_cm}";

sub allegro_printAuctionTimingInfo {
    my $deadlineOffset     = ($auctionEnd - $serverTime);
    my $deadlineOffsetSecs = ($deadlineOffset % 60);
       $deadlineOffset /= 60;
    my $deadlineOffsetMins = ($deadlineOffset % 60);
       $deadlineOffset /= 60;
    my $deadlineOffsetHrs  = ($deadlineOffset % 24);
    my $deadlineOffsetDays = ($deadlineOffset / 24);
       $deadlineOffset     = ($auctionEnd - $serverTime);

    if ($auctionFinished) {
        info("Auction finished! ($deadlineOffsetDays days, $deadlineOffsetHrs hours, $deadlineOffsetMins minutes, $deadlineOffsetSecs seconds ($deadlineOffset seconds))");
    } else {
        my $lastCallStr = ($auctionLastCall ? ' [LAST CALL]' : '');
        info("Auction will end in $deadlineOffsetDays days, $deadlineOffsetHrs hours, $deadlineOffsetMins minutes and $deadlineOffsetSecs seconds ($deadlineOffset seconds)${lastCallStr}");
    }
}

sub allegro_logout {
    get_page('http://allegro.pl/logout.php', 0);

    if ($response->is_success) {
        info('Successful logout');
    } else {
        warning('Error logging out: ' . ($response->status_line));
    }
}

sub allegro_login {
    info("Trying to login as $userName ...");
    get_page('http://allegro.pl/mainpage_login.php', 1);

    if ($response->is_success) {
        debug('got login form [0]');

        my $sslCipher      = $response->header(LWP_CLIENT_SSL_CIPHER);
        my $sslCertSubject = $response->header(LWP_CLIENT_SSL_CERT_SUBJECT);
        my $sslCertIssuer  = $response->header(LWP_CLIENT_SSL_CERT_ISSUER);

        if (($sslCipher) and ($sslCertSubject) and ($sslCertIssuer)) {
            info(LWP_CLIENT_SSL_CIPHER       . ": $sslCipher");
            info(LWP_CLIENT_SSL_CERT_SUBJECT . ": $sslCertSubject");
            info(LWP_CLIENT_SSL_CERT_ISSUER  . ": $sslCertIssuer");
            my @responseForms = HTML::Form->parse($response);

            foreach my $respForm (@responseForms) {
                if (ALLEGRO_FORM_LOGIN_ACTION eq ($respForm->action)) {
                    debug('got login form [1]');

                    my $input_requestServer = $respForm->find_input(ALLEGRO_FF_LOGIN_REQUEST_SERVER, FI_hidden);
                    my $input_submit        = $respForm->find_input(ALLEGRO_FF_LOGIN_SUBMIT,         FI_submit);
                    my $input_userLogin     = $respForm->find_input(ALLEGRO_FF_LOGIN_USER_LOGIN,     FI_text);
                    my $input_userPassword  = $respForm->find_input(ALLEGRO_FF_LOGIN_USER_PASSWORD,  FI_password);

                    if ((defined($input_requestServer)) and (defined($input_submit)) and (defined($input_userLogin)) and (defined($input_userPassword)) and (ALLEGRO_HOST_SSL eq ($input_requestServer->value)) and (ALLEGRO_FF_LOGIN_SUBMIT_VALUE eq ($input_submit->value))) {
                        debug('got login form [2]');

                        $input_userLogin->value($userName);
                        $input_userPassword->value($userPassword);
                        $request = $input_submit->click($respForm);
                        $request->header(LWP_IF_SSL_CERT_SUBJECT, ALLEGRO_HOST_SSL);

                        fatal("Unexpected login form URI!") unless (ALLEGRO_FORM_LOGIN_ACTION eq ($request->uri));
                        fatal("Unexpected login form method") unless (HTTP_METHOD_POST eq ($request->method));

                        debug2($request->as_string);
                           $response     = $userAgent->request($request);      # submit login form
                        my $responseCode = $response->code();

                        if (302 == $responseCode) {
                            my  $hdrLocation = $response->header(HTTP_HEADER_LOCATION);
                            if ($hdrLocation =~ ALLEGRO_FORM_LOGIN_REDIRECT_1) {
                                get_page((ALLEGRO_HOST_SSL_DOCROOT . $hdrLocation), 1);

                                if ($response->is_success) {
                                    my  $hdrRefresh = $response->header(HTTP_HEADER_REFRESH);
                                    if ($hdrRefresh =~ ALLEGRO_FORM_LOGIN_REDIRECT_2) {
                                        get_page($1, 1);

                                        if ($response->is_success) {
                                            updateServerTime();
                                            info("Successfully logged in as $userName");
                                            return 1;
                                        } else {
                                            error($response->as_string);
                                            error("[3] Unable to login as $userName: " . ($response->status_line));
                                        }
                                    }
                                } else {
                                    error($response->as_string);
                                    error("[2] Unable to login as $userName: " . ($response->status_line));
                                }
                            } elsif ($hdrLocation =~ ALLEGRO_FORM_LOGIN_REDIRECT_1_BADPASS) {
                                error("[1] Unable to login as $userName (invalid username or password)");
                            } else {
                                error($response->as_string);
                                error("[1] Unable to login as $userName");
                            }
                        }
                    }

                    last;
                }
            }
        } else {
            error('Error logging in: no SSL!');
        }
    } else {
        error('Error getting login form: ' . ($response->status_line));
    }

    return 0;
}

sub allegro_monthShort2en {
    my $month = shift;
       $month = lc($month);

    return MONTH_JAN if (ALLEGRO_MONTH_JAN eq $month);
    return MONTH_FEB if (ALLEGRO_MONTH_FEB eq $month);
    return MONTH_MAR if (ALLEGRO_MONTH_MAR eq $month);
    return MONTH_APR if (ALLEGRO_MONTH_APR eq $month);
    return MONTH_MAY if (ALLEGRO_MONTH_MAY eq $month);
    return MONTH_JUN if (ALLEGRO_MONTH_JUN eq $month);
    return MONTH_JUL if (ALLEGRO_MONTH_JUL eq $month);
    return MONTH_AUG if (ALLEGRO_MONTH_AUG eq $month);
    return MONTH_SEP if (ALLEGRO_MONTH_SEP eq $month);
    return MONTH_OCT if (ALLEGRO_MONTH_OCT eq $month);
    return MONTH_NOV if (ALLEGRO_MONTH_NOV eq $month);
    return MONTH_DEC if (ALLEGRO_MONTH_DEC eq $month);

    warning("Unknown allegro month: $month");
    return undef;
}

sub allegro_monthShort2int {
    my $month = shift;
       $month = lc($month);

    return  0 if (ALLEGRO_MONTH_JAN eq $month);
    return  1 if (ALLEGRO_MONTH_FEB eq $month);
    return  2 if (ALLEGRO_MONTH_MAR eq $month);
    return  3 if (ALLEGRO_MONTH_APR eq $month);
    return  4 if (ALLEGRO_MONTH_MAY eq $month);
    return  5 if (ALLEGRO_MONTH_JUN eq $month);
    return  6 if (ALLEGRO_MONTH_JUL eq $month);
    return  7 if (ALLEGRO_MONTH_AUG eq $month);
    return  8 if (ALLEGRO_MONTH_SEP eq $month);
    return  9 if (ALLEGRO_MONTH_OCT eq $month);
    return 10 if (ALLEGRO_MONTH_NOV eq $month);
    return 11 if (ALLEGRO_MONTH_DEC eq $month);

    warning("Unknown allegro month: $month");
    return undef;
}

sub allegro_timezone_offset_secs {
    my $tzName = shift;

    return (3600 * 1) if (TZ_CET  eq $tzName);
    return (3600 * 2) if (TZ_CEST eq $tzName);

    warning("Unknown allegro timezone specifier: $tzName");
    return undef;
}

sub allegro_parse_item {
    my $itemPageRef = shift;
    my $itemPage    = ${$itemPageRef};

    if ($itemPage =~ ALLEGRO_AUCTION_TITLE) {
        $auctionTitle = trim($1);
    }

    if ($itemPage =~ m/$g8_deadline/is) {
        my $doKonca    = encode('UTF-8', trim($1));
        my $dayOfMonth = $2;
        my $month      = trim($3);
        my $year       = $4;
        my $hour       = $5;
        my $minute     = $6;
        my $second     = $7;
        my $tzone      = $8;

        my $monthNr     = 1 + allegro_monthShort2int($month);
           $monthNr     = "0${monthNr}" if ($monthNr < 10);
        my $deadlineStr = "$year-$monthNr-$dayOfMonth $hour:$minute:$second";
        my $deadlineTS  = Time::Piece->strptime($deadlineStr, "%Y-%m-%d %H:%M:%S");
           $deadlineTS  = ($deadlineTS->epoch) - allegro_timezone_offset_secs($tzone);

        debug("deadline: $deadlineStr $tzone (do konca: $doKonca) => $deadlineTS");

        $auctionEnd      = $deadlineTS;
        $auctionFinished = 1 if ($doKonca =~ ALLEGRO_AUCTION_FINISHED);
        $auctionLastCall = 1 if ($doKonca =~ ALLEGRO_AUCTION_LASTCALL);
        return 1;
    } else {
        warning('Unable to parse item page!');
    }

    return 0;
}

sub allegro_item {
    get_page(('http://allegro.pl/show_item.php?item=' . $auctionId), 0);
    updateServerTime();

    if ($response->is_success) {
        debug('get item: ' . ($response->status_line));
        return ($response->decoded_content);
    } else {
        error('Error getting item info: ' . ($response->status_line));
        return undef;
    }
}

sub allegro_bid_once {
    info("Trying to bid...");
    my $itemPage = allegro_item();
    return 0 unless (allegro_parse_item(\$itemPage));
    my @prebidForms = HTML::Form->parse($response);

    foreach my $prebidForm (@prebidForms) {
        if (ALLEGRO_FORM_PREBID_ACTION eq ($prebidForm->action)) {
            debug('got pre-bid form [1]');
            my $input_preSubmit = $prebidForm->find_input(ALLEGRO_FF_PREBID_SUBMIT,   FI_submit);
            my $input_preAmount = $prebidForm->find_input(ALLEGRO_FF_PREBID_AMOUNT,   FI_text);
            my $input_preItemId = $prebidForm->find_input(ALLEGRO_FF_PREBID_ITEM_ID,  FI_hidden);

            if ((defined($input_preSubmit)) and (defined($input_preAmount)) and (defined($input_preItemId)) and (($input_preItemId->value) eq $auctionId) and (($input_preSubmit->value) =~ ALLEGRO_FF_PREBID_SUBMIT_VALUE)) {
                debug('got pre-bid form [2]');
                $input_preAmount->value($maxBid);
                $request = $input_preSubmit->click($prebidForm);
                warning('Unexpected pre-bid form method (' . ($request->method) . ')') unless (HTTP_METHOD_POST eq ($request->method));
                debug2($request->as_string);
                $response = $userAgent->request($request);      # submit pre-bid form

                if ($response->is_success) {
                    my @bidForms = HTML::Form->parse($response);

                    foreach my $bidForm (@bidForms) {
                        if (ALLEGRO_FORM_BID_ACTION eq ($bidForm->action)) {
                            debug('got bid form [1]: ' . ($bidForm->action));

                            my $input_itemId   = $bidForm->find_input(ALLEGRO_FF_BID_ITEM_ID,  FI_hidden);
                            my $input_amount   = $bidForm->find_input(ALLEGRO_FF_BID_AMOUNT,   FI_hidden);
                            my $input_quantity = $bidForm->find_input(ALLEGRO_FF_BID_QUANTITY, FI_hidden);
                            my $input_submit   = $bidForm->find_input(ALLEGRO_FF_BID_SUBMIT,   FI_submit);

                            if ((defined($input_itemId)) and (defined($input_amount)) and (defined($input_quantity)) and (defined($input_submit)) and (($input_itemId->value) eq $auctionId) and (($input_submit->value) =~ ALLEGRO_FF_BID_SUBMIT_VALUE)) {
                                debug('got bid form [2]');

                                unless (($input_itemId->value) eq $auctionId) {
                                    error($bidForm->dump);
                                    error("Inconsistent auction id! Expected $auctionId, but got " . ($input_itemId->value) . '. Giving up.');
                                    return 0;
                                }
                                unless (($input_amount->value) eq $maxBid) {
                                    error($bidForm->dump);
                                    error("Inconsistent bid value! Expected $maxBid, but got " . ($input_amount->value) . '. Giving up.');
                                    return 0;
                                }
                                unless (($input_quantity->value) eq 1) {
                                    error($bidForm->dump);
                                    error("Inconsistent quantity value! Expected 1, but got " . ($input_quantity->value) . '. Giving up.');
                                    return 0;
                                }

                                $request = $input_submit->click($bidForm);
                                warning('Unexpected bid form method (' . ($request->method) . ')') unless (HTTP_METHOD_POST eq ($request->method));
                                debug2($request->as_string);
                                $response = $userAgent->request($request);      # submit bid form
                                my $responseCode = $response->code();

                                if (302 == $responseCode) {
                                    my  $hdrLocation = $response->header(HTTP_HEADER_LOCATION);
                                    if ($hdrLocation =~ ALLEGRO_FORM_BID_REDIRECT) {
                                        get_page((ALLEGRO_HOST_DOCROOT . $hdrLocation), 0);

                                        if ($response->is_success) {
                                            info("bid $maxBid as $userName in auction $auctionId");
                                            return 1;
                                        } else {
                                            error($response->as_string);
                                            error('[3] unable to submit bid form: ' . ($response->status_line));
                                        }
                                    } else {
                                        error($response->as_string);
                                        error('[2] unable to submit bid form: ' . ($response->status_line));
                                    }
                                } else {
                                    error($response->as_string);
                                    error('[1] unable to submit bid form: ' . ($response->status_line));
                                }
                            }

                            last;
                        }
                    }
                } else {
                    error('unable to submit pre-bid form: ' . ($response->status_line));
                }
            }

            last;
        }
    }

    return 0;
}

# Sleeps until there is only a specified number of seconds to auction end.
sub allegro_auction_wait {
    my $timeoutReverse     = shift;
    my $auctionEndRelative = ((defined($auctionEnd) and defined($serverTime)) ? ($auctionEnd - $serverTime) : ($timeoutReverse + 100));

    while ((not ($auctionFinished)) and ($auctionEndRelative > $timeoutReverse)) {
        my $itemPage = allegro_item();
        return 0 unless (allegro_parse_item(\$itemPage));
        info($auctionTitle) if (defined($auctionTitle));

        allegro_printAuctionTimingInfo();
        $auctionEndRelative = $auctionEnd - $serverTime;

        if ((not ($auctionFinished)) and ($auctionEndRelative > $timeoutReverse)) {
            my $tts = $auctionEndRelative - $timeoutReverse;
            info("sleep($tts) ...");
            $auctionEndRelative -= sleep($tts);
        }
    }

    if (($auctionFinished) or ($auctionEndRelative < 0)) {
        warning("Auction complete! ($auctionEndRelative)");
    } else {
        info("Auction will expire in $auctionEndRelative seconds: time to act");
        warning("no last call yet") unless ($auctionLastCall);
        return 1;
    }

    return 0;
}

####################################
# Others
####################################

sub getPassword {
    prompt('Enter password: ', -e=>'*');
    $userPassword = $_;
}

sub printHelp {
    my $cookieFileDefault = LWP_COOKIE_FILENAME_DEFAULT();
    my $alshver           = VERSION();
    my $alshverdate       = VERSION_DATE();
    print <<"ENDHELP";
alshooter $alshver ($alshverdate)

Copyright (C) 2010 Stanislaw Findeisen <stf at eisenbits.com>
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/>
This is free software: you are free to change and redistribute it.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A very simple Allegro.pl auction shooter.

Usage:
  $0 --user userName --auctionId auctionId --maxBid maxBid [--cookieFile FILE] [--noTestLogin]

maxBid is your offer. Use only integer numbers here (groschen/cents do not work).

If no cookieFile is specified, $cookieFileDefault is used. This is a cookie
jar to store HTTP cookies received from the server. Use separate files for
different Allegro users. Remove the files afterwards.

alshooter makes an initial login/logout test for you to see if the credentials
work. Then sleeps. Then logs in and bids just before the auction end (3 secs).
Use --noTestLogin to skip the initial login/logout test.
ENDHELP
}

####################################
# The program - main
####################################

my $help          = 0;
my $skipTestLogin = 0;
my $clres = GetOptions('user=s' => \$userName, 'auctionId=s' => \$auctionId, 'maxBid=i' => \$maxBid, 'cookieFile:s' => \$cookieFileName, 'noTestLogin' => \$skipTestLogin, 'help'  => \$help);

if (($help) or (not (($clres) and ($userName) and ($auctionId) and ($maxBid) and (0 <= $maxBid)))) {
    printHelp();
    exit 0;
}

getPassword();
$cookieFileName = LWP_COOKIE_FILENAME_DEFAULT unless ($cookieFileName);
info("user: $userName, auction id: $auctionId, max bid: $maxBid");
info("cookie file : $cookieFileName") if (defined($cookieFileName));

# Crypt::SSLeay configuration
$ENV{HTTPS_VERSION} = 3;
$ENV{HTTPS_DEBUG}   = 1;
# TODO how to make LWP honour just thawte?
$ENV{HTTPS_CA_FILE} = '/etc/ssl/certs/thawte_Primary_Root_CA.pem';

debug('LWP version: ' . ($LWP::VERSION));
create_user_agent();

unless ($skipTestLogin) {
    if (allegro_login()) {
        allegro_logout();
    } else {
        allegro_logout();
        fatal('login problem');
    }
}

fatal('allegro_auction_wait problem') unless (allegro_auction_wait(TTA_SECS_LOGIN));

if (allegro_login()) {
    if (allegro_auction_wait(TTA_SECS_BID)) {
        allegro_bid_once();
    }
}

allegro_logout();
