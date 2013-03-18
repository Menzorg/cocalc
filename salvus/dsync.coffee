###################################################################
#
# Class to support simultaneous multiple editing
# sessions by different clients of a single object.  This uses
# the Differential Synchronization algorithm of Neil Fraser,
# which is the same thing that Google Docs uses.
#
#   * "Differential Synchronization" (by Neil Fraser).
#   * http://neil.fraser.name/writing/sync/
#   * http://www.youtube.com/watch?v=S2Hp_1jqpY8
#   * http://code.google.com/p/google-diff-match-patch/
#
###################################################################


# coffee  -o node_modules -c dsync.coffee && echo "require('dsync').test1()" | coffee

misc = require('misc')
{defaults, required} = misc

diff_match_patch = require('googlediff')  # TODO: this greatly increases the size of browserify output (unless we compress it)

dmp = new diff_match_patch()

class DSync
    constructor: (opts) ->
        opts = defaults opts,
            id   : undefined
            doc  : required
        if not opts.id?
            @id = misc.uuid()
        else
            @id = opts.id

        @live                  = opts.doc
        @shadow                = @_copy(@live)
        @backup_shadow         = @_copy(@shadow)
        @shadow_version        = 0
        @last_version_received = 0
        @edit_stack            = []

    status: () =>
        return {'id':@id, 'live':@live, 'shadow':@shadow, 'shadow_version':@shadow_version, 'edit_stack':@edit_stack}

    restart: (reason) =>
        console.log("*********************************************************")
        console.log("* THINGS WENT TO HELL. -- #{reason} --  HAVE TO RESTART!!!!! *")
        console.log("*********************************************************")
        throw("dang")

    # Copy a document; strings are immutable and the default, so we
    # just return the object.
    _copy: (doc) =>
        return doc

    # Determine array of edits between the two versions of the document
    _compute_edits: (version0, version1) =>
        return dmp.patch_make(version0, version1)

    # "Best effort" application of array of edits.
    _apply_edits: (edits, doc) =>
        return dmp.patch_apply(edits, doc)[0]

    # Return a checksum of a document
    _checksum: (doc) =>
        return doc.length

    # Connect this client to the other end of the connection, the "server".
    connect: (server) =>
        @server = server

    # Create a list of new edits, then send all edits not yet
    # processed to the other end of the connection.
    push_edits: (cb) =>
        edits = {edits:@_compute_edits(@shadow, @live)}

        if edits.edits.length > 0
            edits.shadow_version = @shadow_version
            edits.shadow_checksum = @_checksum(@shadow)
            # console.log("#{@id} -- push_edits -- #{misc.to_json(edits)}")
            @edit_stack.push(edits)
            console.log("#{@id} -- shadow changes: '#{@shadow}' --> '#{@live}'  (version #{@shadow_version+1})")
            @shadow = @_copy(@live)
            @shadow_version += 1
        else
            # console.log("#{@id} -- push_edits -- (nothing new)")

        # Push any remaining edits from the stack, *AND* report the last version we have received so far.
        @server.recv_edits @edit_stack, @last_version_received, cb

    # Receive and process the edits from the other end of the sync connection.
    recv_edits: (edit_stack, last_version_ack, cb) =>

        #console.log("#{@id} -- recv_edits -- #{misc.to_json(edit_stack)}")
        # Keep only edits that we still need to send.
        @edit_stack = (edits for edits in @edit_stack when edits.shadow_version > last_version_ack)

        #console.log("#{@id} -- remaining queued edits for next time: ", @edit_stack)
        # process the incoming edits
        for edits in edit_stack
            console.log("#{@id} -- our shadow version = #{@shadow_version} and client shadow version #{edits.shadow_version}")
            # If edits.shadow_version does not equal @shadow_version, then there was a packet duplication or loss.
            if edits.shadow_version < @shadow_version
                console.log("Duplicate Packet: we have no interest in edits we have already processed.")
                continue
            else if edits.shadow_version > @shadow_version
                @restart('shadow_version out of sync')
            else if edits.shadow_checksum != @_checksum(@shadow)
                # Data corruption in memory or network -- there should be no other way for this to happen.
                # In this case, we have to just restart everything from scratch.
                console.log("#{@id}: shadow = #{@shadow}, version = #{@shadow_version}")
                @restart("checksum (edit_stack=#{misc.to_json(edit_stack)})")
            else
                # Everything looks golden.
                @last_version_received = edits.shadow_version
                console.log("#{@id} -- shadow changes: '#{@shadow}' --> '#{@_apply_edits(edits.edits, @shadow)}' (version #{@shadow_version+1})")
                @shadow = @_apply_edits(edits.edits, @shadow)
                @shadow_version += 1
                @live = @_apply_edits(edits.edits, @live)
                @backup_shadow = @_copy(@shadow)

        cb?()


exports.test1 = () ->
    client = new DSync(doc:"sage", id:"client")
    server = new DSync(doc:"sage", id:"server")
    client.connect(server)
    server.connect(client)

    client.live = "sage"
    server.live = "my\nsage"
    status = () ->
        console.log("------------------------")
        console.log(misc.to_json(client.status()))
        console.log(misc.to_json(server.status()))
        console.log("------------------------")

    status()
    client.push_edits()
    server.push_edits()
    status()

    client.live += "\nmore stuff"
    status()
    client.push_edits()
    server.push_edits()
    status()

    client.push_edits()

    client.live = 'bar1\n' + client.live
    server.live = 'bar2\n'
    status()
    while client.live != server.live
        try
            client.push_edits()
            server.push_edits()
            status()
        catch e
            status()
            break
    status()

exports.DSync = DSync