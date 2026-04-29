/**
 * HTML Clock Plasmoid
 *
 * @author    Marcin Orlowski <mail (#) marcinOrlowski (.) com>
 * @copyright 2020-2026 Marcin Orlowski
 * @license   http://www.opensource.org/licenses/mit-license.php MIT
 * @link      https://github.com/MarcinOrlowski/html-clock-plasmoid
 */

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import "../js/DateTimeFormatter.js" as DTF
import "../js/layouts.js" as Layouts
import "../js/utils.js" as Utils

ColumnLayout {
	id: mainContainer
	spacing: 0

	// Signal to notify parent to toggle expanded state
	signal toggleExpanded()

	// ------------------------------------------------------------------------------------------------------------------------

	property string layoutKey: Plasmoid.configuration.layoutKey
	property bool useUserLayout: Plasmoid.configuration.useUserLayout
	property int activeLayoutSlot: Plasmoid.configuration.activeLayoutSlot
	property bool useCustomFont: Plasmoid.configuration.useCustomFont
	property font customFont: Plasmoid.configuration.customFont
	property bool widgetContainerFillWidth: Plasmoid.configuration.widgetContainerFillWidth
	property bool widgetContainerFillHeight: Plasmoid.configuration.widgetContainerFillHeight
	property int flipInterval: Plasmoid.configuration.flipInterval
	property int cycleIndex: 0
	property int randomInterval: Plasmoid.configuration.randomInterval
	property int randomIndex: 0

	// Resolved user home directory; used to expand {home} in layout templates
	// so absolute paths like {home}/.local/share/... don't hardcode a username.
	readonly property string homeDir: {
		var url = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString()
		return url.indexOf("file://") === 0 ? url.substring(7) : url
	}

	// Flip animation runs in the last flipFrameAnimMs of each tick window.
	readonly property int flipFrameAnimMs: 400
	readonly property int flipFrameCount: 25

	// Cache of last rendered state, used by flipFrameTimer to skip redraws
	// during the rest portion of each tick window. Encoded as a fingerprint
	// string so adding new tracked values stays cheap.
	property string lastFingerprint: ""

	function pad2(n) { return n < 10 ? "0" + n : "" + n }
	function pad4(n) {
		if (n < 10) return "000" + n
		if (n < 100) return "00" + n
		if (n < 1000) return "0" + n
		return "" + n
	}
	function digitFlip(currChar, nextChar, msUntilTick) {
		if (currChar === nextChar) return 0
		return computeFlipFrame(msUntilTick)
	}

	function computeFlipFrame(msUntilTick) {
		if (msUntilTick > flipFrameAnimMs || msUntilTick <= 0) return 0
		var animElapsed = flipFrameAnimMs - msUntilTick
		var idx = Math.floor(animElapsed * flipFrameCount / flipFrameAnimMs) + 1
		return Math.min(flipFrameCount, idx)
	}

	property string onClickAction: Plasmoid.configuration.onClickAction
	property string onClickAppCommand: Plasmoid.configuration.onClickAppCommand

	// DataSource for launching applications
	Plasma5Support.DataSource {
		id: executable
		engine: "executable"
		connectedSources: []
		onNewData: function(source, data) {
			disconnectSource(source)
		}
	}

	function launchApp(command) {
		if (command && command.trim() !== '') {
			executable.connectSource(command)
		}
	}

	Timer {
		id: flipTimer
		interval: flipInterval
		running: true
		repeat: true
		onTriggered: {
			cycleIndex++
			updateClock()
		}
	}

	Timer {
		id: randomTimer
		interval: randomInterval
		running: true
		repeat: true
		onTriggered: {
			randomIndex++
			updateClock()
		}
	}

	Timer {
		id: flipFrameTimer
		interval: 16
		running: true
		repeat: true
		onTriggered: {
			var now = new Date()
			var ms = now.getMilliseconds()
			var sec = now.getSeconds()
			var min = now.getMinutes()
			var hour = now.getHours()
			var day = now.getDate()
			var month = now.getMonth()
			var year = now.getFullYear()
			var msToNextSec = 1000 - ms
			var msToNextMin = (59 - sec) * 1000 + msToNextSec
			var msToNextHour = (59 - min) * 60000 + msToNextMin
			var msToNextDay = new Date(year, month, day + 1).getTime() - now.getTime()
			var msToNextMonth = new Date(year, month + 1, 1).getTime() - now.getTime()
			var msToNextYear = new Date(year + 1, 0, 1).getTime() - now.getTime()
			var fp = sec + "," + min + "," + hour + "," + day + "," + month + "," + year
				+ "," + computeFlipFrame(msToNextSec)
				+ "," + computeFlipFrame(msToNextMin)
				+ "," + computeFlipFrame(msToNextHour)
				+ "," + computeFlipFrame(msToNextDay)
				+ "," + computeFlipFrame(msToNextMonth)
				+ "," + computeFlipFrame(msToNextYear)
			if (fp === lastFingerprint) return
			lastFingerprint = fp
			updateClock()
		}
	}

	// ------------------------------------------------------------------------------------------------------------------------

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		onClicked: {
			switch (onClickAction) {
				case "calendar":
					mainContainer.toggleExpanded()
					break
				case "launchApp":
					launchApp(onClickAppCommand)
					break
				case "disabled":
				default:
					break
			}
		}
	}

	// ------------------------------------------------------------------------------------------------------------------------

	PlasmaComponents.Label {
		id: clock
		Layout.alignment: Qt.AlignHCenter
		textFormat: Text.RichText
		Layout.fillWidth: widgetContainerFillWidth
		Layout.fillHeight: widgetContainerFillHeight

		font.family: useCustomFont ? customFont.family : Qt.application.font.family
		font.pointSize: useCustomFont ? customFont.pointSize : Qt.application.font.pointSize
		font.bold: useCustomFont ? customFont.bold : Qt.application.font.bold
		font.italic: useCustomFont ? customFont.italic : Qt.application.font.italic
		font.underline: useCustomFont ? customFont.underline : Qt.application.font.underline
	}

	Plasma5Support.DataSource {
		engine: "time"
		connectedSources: ["Local", "UTC"]
		interval: 1000
		intervalAlignment: Plasma5Support.Types.NoAlignment
		onDataChanged: updateClock()
	}

	readonly property string layout: Plasmoid.configuration.layout
	property string configTimezoneOffset: Plasmoid.configuration.clockTimezoneOffset
	onLayoutChanged: updateClock()

	function getActiveUserLayout() {
		switch (activeLayoutSlot) {
			case 2: return Plasmoid.configuration.layout2
			case 3: return Plasmoid.configuration.layout3
			default: return Plasmoid.configuration.layout
		}
	}

	function updateClock() {
		var layoutHtml = useUserLayout
				? getActiveUserLayout()
				: Layouts.layouts[layoutKey]['html']
		var localeToUse = Plasmoid.configuration.useSpecificLocaleEnabled
				? Plasmoid.configuration.useSpecificLocaleLocaleName
				: ''
		var finalOffsetOrNull = Plasmoid.configuration.clockTimezoneOffsetEnabled
			? Utils.parseTimezoneOffset(Plasmoid.configuration.clockTimezoneOffset)
			: null
		var txt = layoutHtml.replace(/\{home\}/g, homeDir)
		txt = handleFlip(txt)
		txt = handleCycle(txt)
		txt = handleRandom(txt)
		txt = handleFlipFrame(txt)
		clock.text = DTF.format(txt, localeToUse, finalOffsetOrNull)
	}

	function handleFlip(text) {
		// Support both | (new) and : (legacy) separators
		// flip is just cycle with 2 values, uses cycleIndex % 2
		var patterns = [
			{ reg: /\{flip\|(.+?)\|(.+?)\}/gi, valReg: /^\{flip\|(.+?)\|(.+?)\}$/i },
			{ reg: /\{flip:(.+?):(.+?)\}/gi, valReg: /^\{flip:(.+?):(.+?)\}$/i }
		]
		patterns.forEach(function(pattern) {
			var matches = text.match(pattern.reg)
			if (matches !== null) {
				matches.forEach(function (val) {
					var valMatch = val.match(pattern.valReg)
					text = text.replace(val, valMatch[(cycleIndex % 2) + 1])
				})
			}
		})
		return text
	}

	function handleCycle(text) {
		// Match {cycle|val1|val2|val3|...} with variable number of values
		var reg = /\{cycle\|([^}]+)\}/gi
		var matches = text.match(reg)
		if (matches !== null) {
			matches.forEach(function (val) {
				var valMatch = val.match(/^\{cycle\|([^}]+)\}$/i)
				if (valMatch) {
					var values = valMatch[1].split('|')
					var selectedValue = values[cycleIndex % values.length]
					text = text.replace(val, selectedValue)
				}
			})
		}
		return text
	}

	// Store picked indices keyed by randomIndex and position
	property var randomPicks: ({})       // { randomIndex: { position: pickedIndex } }
	property int randomLastIndex: -1

	function handleRandom(text) {
		// Match {random|val1|val2|val3|...} with variable number of values
		var reg = /\{random\|([^}]+)\}/gi
		var matches = text.match(reg)
		if (matches !== null) {
			// Check if we need to pick new values (randomIndex changed)
			var needNewPick = (randomIndex !== randomLastIndex)
			if (needNewPick) {
				randomLastIndex = randomIndex
				randomPicks[randomIndex] = {}
				// Clean up old entries to prevent memory leak
				for (var key in randomPicks) {
					if (parseInt(key) < randomIndex - 1) {
						delete randomPicks[key]
					}
				}
			}

			var currentPicks = randomPicks[randomIndex] || {}
			var lastPicks = randomPicks[randomIndex - 1] || {}
			var position = 0

			matches.forEach(function (val) {
				var valMatch = val.match(/^\{random\|([^}]+)\}$/i)
				if (valMatch) {
					var values = valMatch[1].split('|')
					var posKey = 'p' + position
					var pickedIndex = currentPicks[posKey]

					if (pickedIndex === undefined) {
						var lastIndex = lastPicks[posKey]

						if (values.length <= 1) {
							pickedIndex = 0
						} else {
							// Pick random index different from last
							do {
								pickedIndex = Math.floor(Math.random() * values.length)
							} while (pickedIndex === lastIndex)
						}
						currentPicks[posKey] = pickedIndex
						randomPicks[randomIndex] = currentPicks
					}

					text = text.replace(val, values[pickedIndex])
					position++
				}
			})
		}
		return text
	}

	function handleFlipFrame(text) {
		var hasFlip = text.indexOf("-flip}") !== -1
		var hasDigit = /\{[hismdy][1-4]\}/.test(text)
		if (!hasFlip && !hasDigit) return text

		var now = new Date()
		var ms = now.getMilliseconds()
		var sec = now.getSeconds()
		var min = now.getMinutes()
		var hour = now.getHours()
		var day = now.getDate()
		var month = now.getMonth()
		var year = now.getFullYear()

		var msToNextSec = 1000 - ms
		var msToNextMin = (59 - sec) * 1000 + msToNextSec
		var msToNextHour = (59 - min) * 60000 + msToNextMin
		var tomorrow = new Date(year, month, day + 1)
		var msToNextDay = tomorrow.getTime() - now.getTime()
		var firstOfNextMonth = new Date(year, month + 1, 1)
		var msToNextMonth = firstOfNextMonth.getTime() - now.getTime()
		var firstOfNextYear = new Date(year + 1, 0, 1)
		var msToNextYear = firstOfNextYear.getTime() - now.getTime()

		var hh = pad2(hour),  nextHH = pad2((hour + 1) % 24)
		var ii = pad2(min),   nextII = pad2((min + 1) % 60)
		var ss = pad2(sec),   nextSS = pad2((sec + 1) % 60)
		var dd = pad2(day),   nextDD = pad2(tomorrow.getDate())
		var mm = pad2(month + 1), nextMM = pad2(firstOfNextMonth.getMonth() + 1)
		var yyyy = pad4(year), nextYYYY = pad4(year + 1)

		// Per-pair flip frames (animate at the boundary regardless of which digits change).
		text = text.replace(/\{hh-flip\}/g, computeFlipFrame(msToNextHour))
		text = text.replace(/\{ii-flip\}/g, computeFlipFrame(msToNextMin))
		text = text.replace(/\{ss-flip\}/g, computeFlipFrame(msToNextSec))
		text = text.replace(/\{dd-flip\}/g, computeFlipFrame(msToNextDay))
		text = text.replace(/\{mm-flip\}/g, computeFlipFrame(msToNextMonth))
		text = text.replace(/\{yyyy-flip\}/g, computeFlipFrame(msToNextYear))

		// Per-digit flip frames (animate only if the specific digit's value changes at this tick).
		text = text.replace(/\{h1-flip\}/g, digitFlip(hh.charAt(0), nextHH.charAt(0), msToNextHour))
		text = text.replace(/\{h2-flip\}/g, digitFlip(hh.charAt(1), nextHH.charAt(1), msToNextHour))
		text = text.replace(/\{i1-flip\}/g, digitFlip(ii.charAt(0), nextII.charAt(0), msToNextMin))
		text = text.replace(/\{i2-flip\}/g, digitFlip(ii.charAt(1), nextII.charAt(1), msToNextMin))
		text = text.replace(/\{s1-flip\}/g, digitFlip(ss.charAt(0), nextSS.charAt(0), msToNextSec))
		text = text.replace(/\{s2-flip\}/g, digitFlip(ss.charAt(1), nextSS.charAt(1), msToNextSec))
		text = text.replace(/\{d1-flip\}/g, digitFlip(dd.charAt(0), nextDD.charAt(0), msToNextDay))
		text = text.replace(/\{d2-flip\}/g, digitFlip(dd.charAt(1), nextDD.charAt(1), msToNextDay))
		text = text.replace(/\{m1-flip\}/g, digitFlip(mm.charAt(0), nextMM.charAt(0), msToNextMonth))
		text = text.replace(/\{m2-flip\}/g, digitFlip(mm.charAt(1), nextMM.charAt(1), msToNextMonth))
		text = text.replace(/\{y1-flip\}/g, digitFlip(yyyy.charAt(0), nextYYYY.charAt(0), msToNextYear))
		text = text.replace(/\{y2-flip\}/g, digitFlip(yyyy.charAt(1), nextYYYY.charAt(1), msToNextYear))
		text = text.replace(/\{y3-flip\}/g, digitFlip(yyyy.charAt(2), nextYYYY.charAt(2), msToNextYear))
		text = text.replace(/\{y4-flip\}/g, digitFlip(yyyy.charAt(3), nextYYYY.charAt(3), msToNextYear))

		// Per-digit value placeholders.
		text = text.replace(/\{h1\}/g, hh.charAt(0))
		text = text.replace(/\{h2\}/g, hh.charAt(1))
		text = text.replace(/\{i1\}/g, ii.charAt(0))
		text = text.replace(/\{i2\}/g, ii.charAt(1))
		text = text.replace(/\{s1\}/g, ss.charAt(0))
		text = text.replace(/\{s2\}/g, ss.charAt(1))
		text = text.replace(/\{d1\}/g, dd.charAt(0))
		text = text.replace(/\{d2\}/g, dd.charAt(1))
		text = text.replace(/\{m1\}/g, mm.charAt(0))
		text = text.replace(/\{m2\}/g, mm.charAt(1))
		text = text.replace(/\{y1\}/g, yyyy.charAt(0))
		text = text.replace(/\{y2\}/g, yyyy.charAt(1))
		text = text.replace(/\{y3\}/g, yyyy.charAt(2))
		text = text.replace(/\{y4\}/g, yyyy.charAt(3))

		return text
	}

	// ------------------------------------------------------------------------------------------------------------------------

} // mainContainer
