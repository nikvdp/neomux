# Contributing 

Pull requests are welcome! If you need to update docs, please make sure to 
update both the markdown and vimdoc versions.

The easiest way I know of to do this is to use the `html2vimdoc.py` script from
[xolox/vim-tools](https://github.com/xolox/vim-tools).

# Updating docs

## Install html2vimdoc

It's a python2 script, so installation is a little weird. On a mac running Big
Sur this is what I did to get a working copy:

- ```
  python2 -m ensurepip --user
  ```
  
- add the pip user dir to your path:
  
  ```
  export PATH=~/Library/Python/2.7/bin:$PATH
  ```
  
- Use the new pip to install `virtualenv`:

 ```
 pip install virtualenv
 ```

- Create and activate the new python2 virtualenv:

  ```
  virtualenv html2vimdoc
  source ./bin/activate
  ```

- Install deps:

  ```
  # (note the ==2.0 for coloredlogs, see https://github.com/xolox/vim-tools/issues/8)
  pip install beautifulsoup markdown coloredlogs==2.0
  ```

- Clone the vim-tools repo:


## Generating the vimdoc file 

With the virtualenv set up you can now finally run the script to generate the
vim formatted docs: 

  ``` 
  # from the folder you cloned vim-tools too: 
  ./html2vimdoc.py -f neomux -t Neomux \
      <neomux-repo>/README.md > <neomux-repo>/doc/neomux.txt
  ```

