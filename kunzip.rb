#!/usr/bin/ruby1.9 -Ku
# encoding: UTF-8
#
#    2010 by ruby.twiddler@gmail.com
#
#      sjis unzip KDE GUI
#

require 'fileutils'

APP_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
APP_NAME = File.basename(APP_FILE).sub(/\.rb/, '')
# APP_DIR = File::dirname(File.expand_path(File.dirname(APP_FILE)))
APP_DIR = File::dirname(File.expand_path(APP_FILE))
LIB_DIR = File::join(APP_DIR, "lib")
APP_VERSION = "0.0.1"


# standard libs
require 'rubygems'
require 'zip/zip'
require 'shellwords'
require 'time'
require 'kconv'

# additional libs
require 'korundum4'
require 'kio'

#
# my libraries and programs
#
$:.unshift(LIB_DIR)
require "mylibs"

#--------------------------------------------------------------------
class FileItem
    attr_reader :name, :date, :size, :sjisname
#     def initialize(frow)
#         @size = frow[0]
#         @date = Time.parse(frow[1] + ' ' + frow[2])
#         @sjisname = frow[3]
#         @name = @sjisname.toutf8
#     end
    def initialize(entry)
        @name = entry.name.toutf8
        @size = entry.size
        @date = entry.time
        @sjisname = entry.name
    end
end

class FileTable < Qt::TableWidget
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end

        def gem
            tableWidget.gem(self)
        end
    end

    def initialize
        super(0, 3)

        setHorizontalHeaderLabels( %w{ Name Date Size } )
        readSettings
    end

    def setFiles(files)
        clearContents
        @files = []
        self.rowCount = files.size
        files.each_with_index do |f, r|
            @files[r] = f
            setItem(r, 0, Item.new(f.name))
            setItem(r, 1, Item.new(f.date.to_s))
            setItem(r, 2, Item.new(f.size))
        end
    end

    def allfiles
#         names = []
#         rowCount.times do |i|
#             names.push(item(i, 0).text)
#         end
#         names
        @files.map do |f| f.sjisname end
    end

    GroupName = "FileTable"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', self.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        self.horizontalHeader.restoreState(config.readEntry('Header', self.horizontalHeader.saveState))
    end
end

#--------------------------------------------------------------------
#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow
    def initialize
        super(nil)

        setCaption(APP_NAME)
        @actions = KDE::ActionCollection.new(self)
        Qt::TextCodec::setCodecForTr(Qt::TextCodec::codecForName("utf-8"));

        createWidget
        createToolBar
        createMenu
        @actions.readSettings
        setAutoSaveSettings
    end

    def createMenu
         # file menu
        quitAction = @actions.addNew('Quit', self, \
            { :icon => 'exit', :shortCut => 'Ctrl+Q', :triggered => :close })
        openAction = @actions.addNew('Open Zip file', self, \
            { :icon => 'open-file', :shortCut => 'Ctrl+O', :triggered => :openFile })
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(openAction)
        fileMenu.addSeparator
        fileMenu.addAction(quitAction)

        # edit menu
        extractAllAction = @actions.addNew('Extract All', self, \
            { :icon => 'extract', :shortCut => 'Ctrl+X', :triggered => :extractAll })
        editMenu = KDE::Menu.new(i18n('Edit'), self)
        editMenu.addAction(extractAllAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( editMenu )
        setMenuBar(menu)
    end

    def createToolBar
    end

    def createWidget
        @fileTable = FileTable.new
        setCentralWidget(@fileTable)
    end



    #------------------------------------
    #
    # virtual slot
    # virtual slot
    def closeEvent(ev)
        @actions.writeSettings
        @fileTable.writeSettings
        super(ev)
        $config.sync    # important!  qtruby can't invoke destructor properly.
    end


    #------------------------------------
    #
    #
    slots :openFile
    def openFile
        # select zip file.
        fileName = KDE::FileDialog::getOpenFileName()
        if fileName && !fileName.empty? && File.exist?(fileName) then
            @zipFile = Zip::ZipFile.open(fileName)
            fileItems = @zipFile.entries.map do |e|
                FileItem.new(e)
            end
            @fileTable.setFiles(fileItems)
        end
    end

    slots :extractAll
    def extractAll
        dirName = KDE::FileDialog::getExistingDirectory()
        if dirName && !dirName.empty? then
            @zipFile.entries.each do |e|
                fname = File.join(dirName, e.name.toutf8)
                e.extract(fname)
            end
        end
    end
end
#------------------------------------------------------------------------------
#
#    main start
#

about = KDE::AboutData.new(APP_NAME, nil, KDE::ki18n(APP_NAME), APP_VERSION,
                            KDE::ki18n('sjis unzip with KDE GUI.')
                           )
about.addLicenseTextFile(APP_DIR + '/MIT-LICENSE')
KDE::CmdLineArgs.init(ARGV, about)

$app = KDE::Application.new
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
