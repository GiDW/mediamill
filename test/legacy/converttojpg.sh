#!/usr/bin/env zsh

# Difference \; and +
# suppose 2 files are found:
# Will execute echo 1 time with both files as input
# find . -type f -exec echo {} +
# Will execute echo 2 times with each 1 file as input
# find . -type f -exec echo {} \;

# vips copy "${1}" "${2}[Q=75,strip,trellis-quant,interlace,optimize-coding,optimize-scans,quant-table=3,subsample_mode=on]"

readonly output_pic_ext='jpg'
readonly vips_mozjpeg_opts='[Q=75,strip,trellis-quant,interlace,optimize-coding,optimize-scans,quant-table=3,subsample_mode=on]'

readonly output_vid_ext='mp4'
readonly ffmpeg_opts=''

readonly input="${1}"
readonly output="${2}"

readonly realinput="$(realpath "${input}")"

readonly convert_info_cmd='\
readonly dest_part="${1/${2}/${3}}";
readonly check_path="${1:r}.jpg";
readonly ext="${1:t:e}";
readonly ext_lower=$(printf '"'"'%s'"'"' "${ext}" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"');

check_ext() \
{ \
    case $1 in \
        jpg ) \
            return 0 \
            ;; \
        jpeg ) \
            return 0 \
            ;; \
        jp2 ) \
            return 0 \
            ;; \
        jfif ) \
            return 0 \
            ;; \
        pjpeg ) \
            return 0 \
            ;; \
        pjp ) \
            return 0 \
            ;; \
        png ) \
            return 0 \
            ;; \
        webp ) \
            return 0 \
            ;; \
        heic ) \
            return 0 \
            ;; \
        * ) \
            return 1 \
            ;; \
    esac; \
} \

if [ "${ext}" != '"'"'jpg'"'"' ] && [ -e "${check_path}" ]; then \
    printf '"'"'\n\nWARNING OVERRIDE\n\nFILE: %s\n\n'"'"' ${1}; \
fi;

printf '"'"'DEST_PART: %s\nDEST: %s\nEXT: %s\nCHECK PATH: %s\nALL: %s\n0: %s\n1: %s\n2: %s\n3: %s\n'"'"' \
"%{dest_part}" \
"${dest_part:r}" \
"${ext}" \
"${check_path}" \
"${${1/${2}/${3}}:r}.jpg" \
"${0}" \
"${1}" \
"${2}" \
"${3}" \


if check_ext "${ext_lower}"; \
then \
    printf '"'"'EXT CONVERT\n'"'"'; \
else \
    printf '"'"'EXT NO CONVERT\n'"'"'; \
fi;
'

readonly convert_cmd='\
readonly out_pic_ext="${4}";
readonly out_vips_opts="${5}";

readonly out_vid_ext="${6}";
readonly out_ffmpeg_opts="${7}";

readonly ext="${1:t:e}";
readonly ext_lower=$(printf '"'"'%s'"'"' "${ext}" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"');
readonly dest="${1/${2}/${3}}";

check_ext() \
{ \
    case $1 in \
        jpg ) \
            return 0 \
            ;; \
        jpeg ) \
            return 0 \
            ;; \
        jp2 ) \
            return 0 \
            ;; \
        jfif ) \
            return 0 \
            ;; \
        pjpeg ) \
            return 0 \
            ;; \
        pjp ) \
            return 0 \
            ;; \
        png ) \
            return 0 \
            ;; \
        webp ) \
            return 0 \
            ;; \
        heic ) \
            return 0 \
            ;; \
        gif ) \
            return 2 \
            ;; \
        * ) \
            return 1 \
            ;; \
    esac; \
} \

check_ext "${ext_lower}"; \
check_ext_result=$?; \

if [ $check_ext_result -eq 0 ]; \
then \
    readonly dest_base="${${dest}:r}"; \
    dest_img="${dest_base}.${out_pic_ext}"; \

    if [ "${ext}" != "${out_pic_ext}" ]; then \
        readonly check_path="${1:r}.${out_pic_ext}"; \
        if [ -e "${check_path}" ]; then \
            readonly inode_input=$(ls -Li ${1} | awk '"'"'{print $1}'"'"'); \
            readonly inode_dest=$(ls -Li ${check_path} | awk '"'"'{print $1}'"'"'); \
            # Check filesystem inodes to check if paths point to same file \
            # Workaround for case-insensitive file systems \
            if [ "${inode_input}" -ne "${inode_dest}" ]; then \
                dest_img="${dest_base}_2.${out_pic_ext}"; \
            fi; \
        fi; \
    fi; \

    vips copy "${1}" "${dest_img}${out_vips_opts}"; \
elif [ $check_ext_result -eq 2 ]; \
then \
    readonly dest_base="${${dest}:r}"; \
    dest_vid="${dest_base}.${out_vid_ext}"; \

    if [ "${ext}" != "${out_vid_ext}" ]; then \
        readonly check_path="${1:r}.${out_vid_ext}"; \
        if [ -e "${check_path}" ]; then \
            dest_vid="${dest_base}_2.${out_vid_ext}"; \
        fi; \
    fi; \

    ffmpeg -i "${1}" \
        -movflags faststart \
        -pix_fmt yuv420p \
        -vf '"'"'scale=trunc(iw/2)*2:trunc(ih/2)*2'"'"' \
        -crf 24 \
        -preset slow \
        "${dest_vid}"; \
else \
    cp "${1}" "${dest}"; \
fi;
'

print_help()
{
    printf 'usage converttojpg.sh <input> <output>\n\n';
    printf '  converttojpg.sh input_dir output_dir\n';
}

copy_directory_structure()
{
    mkdir -p "${output}"
    readonly realoutput="$(realpath "${output}")"
    printf 'Creating structure...\n'
    # find "${realinput}" -type d \
    # -exec zsh -c 'printf '"'"'dest: $s\n0: %s\n1: %s\n2: %s\n3: %s\n4: %s\n5: %s\n'"'"' ${1/${2}/${3}} ${0} ${1} ${2} ${3} ${4} ${5}' _ {} "${realinput}" "${realoutput}" \;
    find "${realinput}" -type d \
    -exec zsh -c 'mkdir -p ${1/${2}/${3}}' _ {} "${realinput}" "${realoutput}" \;
}

convert_images()
{
    readonly realoutput="$(realpath "${output}")"

    printf 'Copying/converting files...\n'

    find "${realinput}" -type f \
    -exec zsh -c "${convert_cmd}" _ {} "${realinput}" "${realoutput}" "${output_pic_ext}" "${vips_mozjpeg_opts}" "${output_vid_ext}" "${ffmpeg_opts}" \;
}

check_ext()
{
    case $1 in
        jpg )
            return 0
            ;;
        jpeg )
            return 0
            ;;
        jp2 ) \
            return 0 \
            ;; \
        jfif )
            return 0
            ;;
        pjpeg )
            return 0
            ;;
        pjp )
            return 0
            ;;
        png )
            return 0
            ;;
        webp )
            return 0
            ;;
        heic )
            return 0
            ;;
        gif )
            return 2
            ;;
        * )
            return 1
            ;;
    esac;
}

if [ -f "${input}" ]
then
    readonly ext="${1:t:e}";
    readonly ext_lower=$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]');

    check_ext "${ext_lower}";
    check_ext_result=$?;

    if [ $check_ext_result -eq 0 ]
    then
        if [ -z "${output}" ]
        then
            # No output given
            # => generate output with name based on input filename
            readonly inputbasename="${input:t:r}"
            newoutputname="${inputbasename}.${output_pic_ext}"
            counter=1
            while [ -e "${newoutputname}" ]
            do
                counter=$((counter+1))
                newoutputname="${inputbasename}_${counter}.${output_pic_ext}"
            done

            vips copy "${input}" "${newoutputname}${vips_mozjpeg_opts}"
        elif [ -d "${output}" ]
        then
            # Output is dir
            printf 'Output is a directory\n\n'
            print_help
        else
            vips copy "${input}" "${output}${vips_mozjpeg_opts}";
        fi
    elif [ $check_ext_result -eq 2 ]
    then
        if [ -z "${output}" ]
        then
            # No output given
            # => generate output with name based on input filename
            readonly inputbasename="${input:t:r}"
            newoutputname="${inputbasename}.${output_vid_ext}"
            counter=1
            while [ -e "${newoutputname}" ]
            do
                counter=$((counter+1))
                newoutputname="${inputbasename}_${counter}.${output_vid_ext}"
            done

            ffmpeg -i "${input}" \
                -movflags faststart \
                -pix_fmt yuv420p \
                -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
                -crf 24 \
                -preset slow \
                "${newoutputname}";
        elif [ -d "${output}" ]
        then
            # Output is dir
            printf 'Output is a directory\n\n'
            print_help
        else
            ffmpeg -i "${input}" \
                -movflags faststart \
                -pix_fmt yuv420p \
                -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
                -crf 24 \
                -preset slow \
                "${output}";
        fi
    else
        printf 'Unsupported file\n';
    fi
elif [ -d "${input}" ]
then
    if [ -z "${output}" ]
    then
        printf 'No output given\n\n'
        print_help
    elif [ -f "${output}" ]
    then
        printf 'Output is a file\n\n';
        print_help
    else
        if ! [ -e "${output}" ]
        then
            mkdir "${output}";
        fi
        copy_directory_structure
        convert_images
    fi
else
    printf 'Unsupported input\n\n';
    print_help
fi
