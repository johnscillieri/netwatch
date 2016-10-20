# The MIT License (MIT)

# Copyright (c) 2014 Hitesh Jasani

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Modified 2016 for netwatch to fix some bugs and add some features

import math
import sequtils
import strutils

const secs_in_ms = 1000
const ms_in_min = 60 * secs_in_ms
const ms_in_hour = 60 * ms_in_min
const ms_in_day = 24 * ms_in_hour
const ms_in_year = 365 * ms_in_day
const ms_units = [ ms_in_year, ms_in_day, ms_in_hour, ms_in_min, secs_in_ms, 1 ]
const suffixes = [ "y", "d", "h", "m", "s", "ms" ]

proc getTimeArray[T]( elapsedTime: T ): seq[string] =
  result = @[]
  var remainder = round(elapsedTime.float64*1000).int
  for i, ms_in_unit in ms_units:
    let unit = remainder div ms_in_unit
    # Only add years/days if they're needed so we don't break backwards compatibility
    if unit == 0 and (suffixes[i] == "y" or suffixes[i] == "d"): continue
    if unit != 0: remainder -= ( unit * ms_in_unit )
    result.add( $unit & suffixes[i] )

proc humanize*[T](elapsedTime: T): string =
  ## Turn a delta time into a human readable string
  ##
  ## humanize(4.031) => 4s 31ms
  let timeArr: seq[string] = getTimeArray( elapsedTime )
  let nonZero = filter( timeArr, proc( time: string ): bool = not time.startswith("0") )
  result = if len( nonZero ) != 0: nonZero.join( " " ) else: "0ms"

proc humanize_max*[T](elapsedTime: T): string =
  ## Turn a delta time into a human readable string that is only the highest term
  ##
  ## humanize_max(4.031) => 4s
  result = humanize( elapsedTime ).split( " " )[0]

proc robotize*[T](elapsedTime: T): string =
  ## Turn a delta time into a robot readable string
  ##
  ## robotize(4.031) => 0h 0m 4s 31ms
  result = getTimeArray( elapsedTime ).join( " " )

template test[T]( input: T, h_output, hmax_output, r_output: string ) =
  test $input:
    check( h_output == humanize(input) )
    check( hmax_output == humanize_max(input) )
    check( r_output == robotize(input) )

when isMainModule:
  import unittest

  test( 0, "0ms", "0ms", "0h 0m 0s 0ms" )
  test( 0.025, "25ms", "25ms", "0h 0m 0s 25ms" )
  test( 3.019, "3s 19ms", "3s", "0h 0m 3s 19ms" )
  test( 4.009, "4s 9ms", "4s", "0h 0m 4s 9ms" )
  test( 9.0, "9s", "9s", "0h 0m 9s 0ms" )
  test( 59.999, "59s 999ms", "59s", "0h 0m 59s 999ms" )
  test( 60.009, "1m 9ms", "1m", "0h 1m 0s 9ms" )
  test( 64.009, "1m 4s 9ms", "1m", "0h 1m 4s 9ms" )
  test( 124.009, "2m 4s 9ms", "2m", "0h 2m 4s 9ms" )
  test( 164.023, "2m 44s 23ms", "2m", "0h 2m 44s 23ms" )
  test( 3600, "1h", "1h", "1h 0m 0s 0ms" )
  test( 4000, "1h 6m 40s", "1h", "1h 6m 40s 0ms" )
  test( 4000.243, "1h 6m 40s 243ms", "1h", "1h 6m 40s 243ms" )
  test( 25.0 * 60.0 * 60.0, "1d 1h", "1d", "1d 1h 0m 0s 0ms" )
  test( 366 * 24.0 * 60.0 * 60.0, "1y 1d", "1y", "1y 1d 0h 0m 0s 0ms" )
  test( 31567712400, "1001y 2d 1h", "1001y", "1001y 2d 1h 0m 0s 0ms" )
