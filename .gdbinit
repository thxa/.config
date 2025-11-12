# ~/.gdbinit for Pwngdb + Pwntools
# source ~/.gef-2025.01.py

# set debug python on
# source /opt/gef/gef.py 
# set remote interrupt-on-connect on
# define c
    # gef config context.enable 0
    # continue
    # gef config context.enable 1
# end
source ~/.gef/gef.py

