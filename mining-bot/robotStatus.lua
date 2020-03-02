local component = require("component")
component.modem.open(80)
while true do
    local e = {event.pull('modem_message')}
    print('State: '..e[6]..', X,Y,Z,Direction: '..e[7]..', message: '..e[8]..', energyPercent: '..e[9]..', time: '..e[10])
end