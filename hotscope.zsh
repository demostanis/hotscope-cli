#!/bin/zsh

VIDEO_PLAYER=mpv
IMAGE_VIEWER=feh
MAIN_URL=https://hotscope.tv

length=
data=
group=porn
page=1
get_data() {
	rdata=$(http $MAIN_URL/$1 |\
		xmllint --html --xpath '//script[@id="__NEXT_DATA__"]/text()' - 2>/dev/null)

	if [ -n "$rdata" ]; then
		# Remove <!CDATA[[ ]]>
		cdata=${rdata:9: -3}
		data=$(jq .props.pageProps.videos <<< "$cdata")
		length=$(($(jq length <<< "$data")-1))
	else
		echo "Hotscope.tv didn't return the correct data.
It is possible that you have been rate limited or that
the website's inner workings have changed. Try to wait
a few minutes or update the app."
		return 1
	fi
}

get_info() {
	video_id=$(jq -r .\[$(($1-1))\].id <<< "$data")
	video_group=$(jq -r .\[$(($1-1))\].group <<< "$data")
	if [ $video_group = other ]; then video_group=$group; fi
	video_rdata=$(http $MAIN_URL/$video_group/$video_id |\
		xmllint --html --xpath '//script[@id="__NEXT_DATA__"]/text()' - 2>/dev/null)

	video_cdata=${video_rdata:9: -3}
	video_data=$(jq .props.pageProps.video <<< "$video_cdata")

	jq -j '
		.title,
		", uploaded by ", .uploader.name,
		" | ", .views, " views\n",
		if .models | length > 0 then
			"models: ", (.models | join(", "))
		else
			"unknown models "
		end
		, "| notes: ", (.votes | to_entries[] | .key, ": ", .value, " ")
		, "\n"
	' <<< "$video_data"
}

check_video() {
	if [ $1 -gt $((length+1)) ]; then
		echo Invalid video.
		continue
	fi
}

fetch_video() {
	video_id=$(jq -r .\[$(($1-1))\].id <<< "$data")
	video_group=$(jq -r .\[$(($1-1))\].group <<< "$data")
	if [ $video_group = other ]; then video_group=$group; fi
	http $MAIN_URL/$video_group/$video_id | xmllint --html \
		--xpath 'string(//video/@src)' - 2>/dev/null
}

download_video() {
	name=$(jq -r .\[$(($1-1))\].title <<< "$data")
	echo -n Downloading $name...
	video=$(fetch_video $1)
	http -o "$name.$(cut -d. -f4 <<< "$video")" "$video"
	echo \ done.
}

get_thumbnail() {
	jq -r .\[$(($1-1))\].image <<< "$data"
}

get_thumbnails() {
	jq -r .\[\].image <<< "$data"
}

list() {
	echo $group \| page $page
	for i in {0..$length}; do
		video=$(jq .\[$i\] <<< "$data")
		printf %d.\  $((i+1)) && jq -r .title <<< "$video"
	done
}

get_data $group
[ -n "$data" ] || exit 1
list

last=
while true; do
	printf "Your choice: ([1-$length] or ? for help) " && read ANSWER
	case $ANSWER in
		\?)
			echo "Help:
? - display this message
n - next page
p - previous page
i - watch ith video
in - go i pages forward
ip - go i pages backward
is - show ith video's preview
id - download ith video
ii - show info for ith video
c - set current category
l - list current page's videos
a - show all the current page's thumbnails
/ - search videos
q - quit

If i is omitted for s and d, the last
selected video is choosen.

Examples:
c snapchat - snapchat videos
8 - watch the 8th video
17s - show 17th video's thumbnail
d - downloads the 17th video (because of 17s)
18i - shows info for the 18th video
3n - go 3 pages forward (1 -> 4)
p - go to the previous page (4 -> 3)"
			;;
		# Ugly way of matching a 1 or 2 digits integer
		[0-9]|[0-9][0-9])
			check_video $ANSWER

			last=$ANSWER
			fetch_video $ANSWER | \
				xargs $VIDEO_PLAYER
			;;
		[0-9]s|[0-9][0-9]s)
			video=${ANSWER%s}
			check_video $video

			last=$video
			image=$(get_thumbnail $video)
			$IMAGE_VIEWER $image
			;;
		a)
			$IMAGE_VIEWER -\^ Catalog -t --index-info %u $(get_thumbnails)
			echo
			;;
		s)
			image=$(get_thumbnail $last)
			$IMAGE_VIEWER $image
			;;
		[0-9]d|[0-9][0-9]d)
			video=${ANSWER%d}
			check_video $video

			last=$video
			download_video $video
			;;
		i)
			last=${ANSWER%d}
			get_info $last
			;;
		[0-9]i|[0-9][0-9]i)
			video=${ANSWER%i}
			get_info $video
			;;
		d)
			download_video $last
			;;
		n)
			page=$(($page+1))
			get_data $group\?page=$page && list
			;;
		[0-9]n|[0-9][0-9]n)
			page=$(($page+${ANSWER%n}))
			get_data $group\?page=$page && list
			;;
		p)
			page=$(($page-1))
			get_data $group\?page=$page && list
			;;
		[0-9]p|[0-9][0-9]p)
			page=$(($page-${ANSWER%p}))
			get_data $group\?page=$page && list
			;;
		l)
			list
			;;
		'c '*)
			choice=${ANSWER:2}
			if [[ "$choice" =~ "^porn|snapchat|periscope|recent$" ]]; then
				group=$choice
			else
				echo Please choose one of: porn, snapchat, periscope, recent.
			fi
			get_data $group\?page=$page && list
			;;
		/*)
			query=${ANSWER:1}
			if [ -n "$query" ]; then
				get_data search/"$query" && list
			fi
			;;
		q)
			echo Hope you cummed, see you soon\!
			bye
			;;
		*)
			if [ -z "$ANSWER" ]; then
				echo
				echo Hope you cummed, see you soon\!
				bye
			else
				echo I didn\'t understand that. Can you try again\?
			fi
			;;
	esac
done

